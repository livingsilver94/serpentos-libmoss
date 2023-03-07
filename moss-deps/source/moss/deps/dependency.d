/*
 * SPDX-FileCopyrightText: Copyright © 2020-2023 Serpent OS Developers
 *
 * SPDX-License-Identifier: Zlib
 */

/**
 * moss.deps.dependency
 *
 * Define the notion of dependencies, providers and their type, along with
 * supporting fromString and toString methods.
 *
 * Authors: Copyright © 2020-2023 Serpent OS Developers
 * License: Zlib
 */
module moss.deps.dependency;

public import std.stdint : uint8_t;

import moss.core.encoding;
import std.array : array;
import std.exception : enforce;
import std.regex : ctRegex, matchAll;
import std.string : format;

/**
 * Regex to capture type(target) dependency/provider strings
 */
private static immutable auto reDepString = `^([a-z]+)\(([a-zA-Z0-9_\-\.]+)\)$`;
private static auto reDep = ctRegex!reDepString;

private static DependencyType[string] depLookupTable;

static this()
{
    depLookupTable["binary"] = DependencyType.BinaryName;
    depLookupTable["sysbinary"] = DependencyType.SystemBinaryName;
    depLookupTable["cmake"] = DependencyType.CmakeName;
    depLookupTable["name"] = DependencyType.PackageName;
    depLookupTable["pkgconfig"] = DependencyType.PkgconfigName;
    depLookupTable["python"] = DependencyType.PythonName;
    depLookupTable["soname"] = DependencyType.SharedLibraryName;
    depLookupTable.rehash();
}

/**
 * Construct T (Dependency or Provider) from input string
 * We only permit one match!
 */
public T fromString(T)(in string inp) if (is(T == Dependency) || is(T == Provider))
{
    auto results = inp.matchAll(reDep);
    if (results.empty)
    {
        return T(inp, DependencyType.PackageName);
    }

    auto match = results.front;
    immutable auto key = match[1];
    immutable auto target = match[2];

    auto lookup = key in depLookupTable;
    enforce(lookup !is null, ".fromString(): Unknown type: %s".format(key));
    return T(target, *lookup);
}

package auto dependencyToString(in DependencyType type, in string target)
{
    final switch (type)
    {
    case DependencyType.PackageName:
        return format!"name(%s)"(target);
    case DependencyType.SharedLibraryName:
        return format!"soname(%s)"(target);
    case DependencyType.PkgconfigName:
        return format!"pkgconfig(%s)"(target);
    case DependencyType.Interpreter:
        return format!"interpreter(%s)"(target);
    case DependencyType.CmakeName:
        return format!"cmake(%s)"(target);
    case DependencyType.PythonName:
        return format!"python(%s)"(target);
    case DependencyType.BinaryName:
        return format!"binary(%s)"(target);
    case DependencyType.SystemBinaryName:
        return format!"sysbinary(%s)"(target);
    }
}
/**
 * A supported dependency has only a limited number of types,
 * which are generated by moss-deps and consumed by us too.
 */
public enum DependencyType : uint8_t
{
    /**
     * A basic name dependency
     */
    PackageName,

    /**
     * Depends on a specific ELF SONAME
     */
    SharedLibraryName,

    /**
     * Provided by the name field of the pkgconfig .pc file
     */
    PkgconfigName,

    /**
     * A special kind of dependency denoting which program or
     * script interpreter is required to run a specific file.
     */
    Interpreter,

    /**
     * Provided by the filename of a Config.cmake or -config.cmake file
     */
    CmakeName,

    /**
     * Python package name from the METADATA or PKG-INFO
     */
    PythonName,

    /**
     * A binary exported from the /usr/bin tree
     */
    BinaryName,

    /**
     * A binary exported from the /usr/sbin tree
     */
    SystemBinaryName,
}

/**
 * A Dependency is an explicit relationship between two packages. Specialised
 * dependencies do exist for matching.
 */
public struct Dependency
{
    /**
     * The dependant target string
     */
    string target = null;

    /**
     * Type of the dependency
     */
    DependencyType type = DependencyType.PackageName;

    /**
     * Return true if both dependencies are equal
     */
    bool opEquals()(auto ref const Dependency other) const
    {
        return other.target == target && other.type == type;
    }

    /**
     * Compare two dependencies with the same type
     */
    int opCmp(ref const Dependency other) const
    {
        if (this.target < other.target)
        {
            return -1;
        }
        else if (this.target > other.target)
        {
            return 1;
        }
        if (this.type < other.type)
        {
            return -1;
        }
        else if (this.type > other.type)
        {
            return 1;
        }
        return 0;
    }

    /**
     * Return the hash code for the label
     */
    ulong toHash() @safe nothrow const
    {
        return typeid(string).getHash(&target);
    }

    /**
     * Encode Dependency into immutable(ubyte[])
     */
    pure ImmutableDatum mossEncode() @trusted const
    {
        return cast(ImmutableDatum)(
                cast(Datum)(type.mossEncode()) ~ cast(Datum)(target.mossEncode()));
    }

    /**
     * Decode a Dependency from immutable(ubyte[])
     */
    pure void mossDecode(in ImmutableDatum rawBytes) @trusted
    {
        enforce(rawBytes.length >= DependencyType.sizeof + 1);
        auto segmentStart = rawBytes[0 .. DependencyType.sizeof];
        auto remnant = rawBytes[DependencyType.sizeof .. $];

        type.mossDecode(segmentStart);
        target.mossDecode(remnant);
    }

    auto toString() const
    {
        return dependencyToString(type, target);
    }
}

/**
 * A Provider is virtually identical to a Dependency but we have a solid definition
 * for type safety purposes
 */
public struct Provider
{
    /**
     * The dependant target string
     */
    string target = null;

    /**
     * Type of the provides
     */
    ProviderType type = ProviderType.PackageName;

    /**
     * Return true if both providers are equal
     */
    bool opEquals()(auto ref const Provider other) const
    {
        return other.target == target && other.type == type;
    }

    /**
     * Compare two providers with the same type
     */
    int opCmp(ref const Provider other) const
    {
        if (this.target < other.target)
        {
            return -1;
        }
        else if (this.target > other.target)
        {
            return 1;
        }
        if (this.type < other.type)
        {
            return -1;
        }
        else if (this.type > other.type)
        {
            return 1;
        }
        return 0;
    }

    /**
     * Return the hash code for the provider
     */
    ulong toHash() @safe nothrow const
    {
        return typeid(string).getHash(&target);
    }

    /**
     * Encode Provider into immutable(ubyte[])
     */
    pure ImmutableDatum mossEncode() @trusted const
    {
        return cast(ImmutableDatum)(
                cast(Datum)(type.mossEncode()) ~ cast(Datum)(target.mossEncode()));
    }

    /**
     * Decode a Provider from immutable(ubyte[])
     */
    pure void mossDecode(in ImmutableDatum rawBytes) @trusted
    {
        enforce(rawBytes.length >= ProviderType.sizeof + 1);
        auto segmentStart = rawBytes[0 .. ProviderType.sizeof];
        auto remnant = rawBytes[ProviderType.sizeof .. $];

        type.mossDecode(segmentStart);
        target.mossDecode(remnant);
    }

    auto toString() const
    {
        return dependencyToString(type, target);
    }
}

/**
 * In our model, A DependencyType is satisfied by the same ProviderType
 */
public alias ProviderType = DependencyType;