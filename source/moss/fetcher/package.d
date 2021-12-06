/*
 * This file is part of moss-fetcher.
 *
 * Copyright © 2020-2021 Serpent OS Developers
 *
 * This software is provided 'as-is', without any express or implied
 * warranty. In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

module moss.fetcher;

import etc.c.curl;
import moss.fetcher.queue;
import moss.fetcher.worker;
import std.exception : enforce;
import std.parallelism : task, totalCPUs, TaskPool;
import std.typecons : Nullable;
import std.range : iota;
import std.algorithm : each, map;

public import moss.core.fetchcontext;

/**
 * Internally we handle work allocation so must know if the work is no
 * longer available.
 */
package alias NullableFetchable = Nullable!(Fetchable, Fetchable.init);

/**
 * A fairly simple implementation of the FetchContext. Downloads added to
 * this fetcher are subject to sorting by *expected size* and grouped by
 * their URI.
 *
 * The largest pending downloads will typically download on the main thread
 * while the remaining threads will gobble up all the small jobs, hopefully
 * leading to better distribution.
 *
 * In a lame attempt at optimisation we support connection reuse as well as
 * sharing the shmem cache between curl handles (CURLSH)
 */
public final class Fetcher : FetchContext
{
    /**
     * Construct a new Fetcher with the given number of worker thread
     */
    this(uint nWorkers = totalCPUs() - 1)
    {
        /* Ensure we always have at LEAST 1 worker */
        if (nWorkers < 1)
        {
            nWorkers = 1;
        }

        this.nWorkers = nWorkers;
        shmem = curl_share_init();
        enforce(shmem !is null, "Fetcher(): curl_share_init() failure");
        setupShare();

        queue = new FetchQueue();

        /* Create N workers, worker 0 preferring large items first */
        foreach (i; 0 .. nWorkers)
        {
            auto pref = i == 0 ? WorkerPreference.LargeItems : WorkerPreference.SmallItems;
            workers[i] = new FetchWorker(shmem, pref);
        }
    }

    /**
     * Enqueue a fetchable for future processing
     */
    override void enqueue(in Fetchable f)
    {
        queue.enqueue(f);
    }

    /**
     * For every download currently enqueued, process them all and
     * return from this function when done.
     */
    override void fetch()
    {
        auto tp = new TaskPool(nWorkers);
        auto tasks = iota(0, nWorkers).map!((w) {
            auto t = task(() => workers[w].run(this));
            tp.put(t);
            return t;
        });
        /* Will ensure that we're at least starting one on main thread */
        tasks.each!((t) => t.spinForce());
        tp.finish(true);
    }

    /**
     * Close this fetcher and any associated resources
     */
    void close()
    {
        if (shmem is null)
        {
            return;
        }

        /* Destroy our workers */
        foreach (ref worker; workers)
        {
            worker.close();
            worker.destroy();
        }
        workers = null;

        /* Destroy curl share */
        curl_share_cleanup(shmem);
        shmem = null;
    }

package:

    /**
     * Allocate work for a worker according to their own work preference.
     * If no more work is available, the returned type will return true
     * in isNull
     */
    NullableFetchable allocateWork(WorkerPreference preference)
    {
        synchronized (queue)
        {
            if (queue.empty)
            {
                return NullableFetchable();
            }
            return NullableFetchable(preference == WorkerPreference.LargeItems
                    ? queue.popLargest : queue.popSmallest);
        }
    }

private:

    /**
     * Setup the sharing aspects
     */
    void setupShare()
    {
        CURLcode ret;

        /* We want to share DNS, SSL session and connection pool */
        ret = curl_share_setopt(shmem, CurlShOption.share,
                CurlLockData.dns | CurlLockData.ssl_session | CurlLockData.connect);
        enforce(ret == 0, "Fetcher.setupShare(): Failed to set CURLSH options");

        /* Set up locking behaviour */
        ret = curl_share_setopt(shmem, CurlShOption.lockfunc, &mossFetcherLockFunc);
        enforce(ret == 0, "Fetcher.setupShare(): Failed to set lock function");
        ret = curl_share_setopt(shmem, CurlShOption.unlockfunc, &mossFetcherUnlockFunc);
        enforce(ret == 0, "Fetcher.setupShare(): Failed to set unlock function");
        ret = curl_share_setopt(shmem, CurlShOption.userdata, this);
        enforce(ret == 0, "Fetcher.setupShare(): Failed to set lock userdata");
    }

    /**
     * Curl requested we lock something
     */
    extern (C) static void mossFetcherLockFunc(void* handle, int data,
            CurlLockData lockType, void* userptr)
    {
        auto fetcher = cast(Fetcher) userptr;
        enforce(fetcher !is null && data >= 0 && data < fetcher.workers.length, "CURL IS BROKEN");
        fetcher.workers[data].lock(lockType);
    }

    /**
     * Curl requested we unlock something
     */
    extern (C) static void mossFetcherUnlockFunc(void* handle, int data,
            CurlLockData lockType, void* userptr)
    {
        auto fetcher = cast(Fetcher) userptr;
        enforce(fetcher !is null && data >= 0 && data < fetcher.workers.length, "CURL IS BROKEN");
        fetcher.workers[data].unlock(lockType);
    }

    CURLSH* shmem = null;
    uint nWorkers = 0;
    FetchQueue queue = null;
    FetchWorker[] workers;
}

private unittest
{
    auto f = new Fetcher();
}
