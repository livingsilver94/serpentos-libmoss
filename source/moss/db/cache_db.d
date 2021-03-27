/*
 * This file is part of moss.
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

/**
 * The moss.db module provides database access routines, highly specialised
 * for use within moss.
 */

module moss.db.cache_db;

import moss.db.disk;

/**
 * The CacheDB is responsible for keeping track of all assets on disk as well
 * as their refcounts.
 *
 * An asset is anything we extract from moss archives prior to use via linking
 */
final class CacheDB
{

public:

    @disable this();

    /**
     * Construct a new CacheDB from the given system root directory
     */
    this(const(string) systemRoot)
    {
        permaStore = new DiskDB(systemRoot, "cache");
    }

private:

    DiskDB permaStore;
}
