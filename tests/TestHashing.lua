local lu = require('luaunit')

TestHashing = {}

local function prepareStorage()
    local storage = {
        { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        { type = "int", alias = "Count", configKey = "Count", default = 1, min = 0, max = 7 },
        { type = "string", alias = "Name", configKey = "Name", default = "A", maxLen = 32 },
        { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 32 },
        { type = "bool", alias = "RecordingArmed", configKey = "RecordingArmed", default = false, runtime = true },
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 2, min = 0, max = 3 },
            },
        },
    }
    AdamantModpackLib_Internal.storage.validate(storage, "HashingTest")
    return storage
end

function TestHashing:testRootsExcludeTransientNodesAndAliasesIncludePackedBits()
    local storage = prepareStorage()
    local roots = lib.hashing.getRoots(storage)
    local aliases = lib.hashing.getAliases(storage)

    lu.assertEquals(#roots, 4)
    lu.assertEquals(roots[1].alias, "EnabledFlag")
    lu.assertEquals(roots[4].alias, "Packed")
    lu.assertNotNil(aliases.FilterText)
    lu.assertNotNil(aliases.RecordingArmed)
    lu.assertNotNil(aliases.EnabledBit)
    lu.assertNotNil(aliases.ModeBits)
end

function TestHashing:testHashCodecRoundTripsSupportedStorageTypes()
    local storage = prepareStorage()
    local aliases = lib.hashing.getAliases(storage)

    lu.assertEquals(lib.hashing.toHash(aliases.EnabledFlag, true), "1")
    lu.assertTrue(lib.hashing.fromHash(aliases.EnabledFlag, "1"))
    lu.assertEquals(lib.hashing.toHash(aliases.Count, 6), "6")
    lu.assertEquals(lib.hashing.fromHash(aliases.Count, "99"), 7)
    lu.assertEquals(lib.hashing.toHash(aliases.Name, "Athena"), "Athena")
    lu.assertEquals(lib.hashing.fromHash(aliases.Name, "Apollo"), "Apollo")
    lu.assertEquals(lib.hashing.toHash({ type = "unknown" }, "x"), nil)
    lu.assertEquals(lib.hashing.fromHash({ type = "unknown" }, "x"), nil)
end

function TestHashing:testPackWidthAndPackedBitReadWrite()
    local storage = prepareStorage()
    local aliases = lib.hashing.getAliases(storage)

    lu.assertEquals(lib.hashing.getPackWidth(aliases.EnabledFlag), 1)
    lu.assertEquals(lib.hashing.getPackWidth(aliases.Count), 3)
    lu.assertEquals(lib.hashing.getPackWidth(aliases.Name), nil)
    lu.assertEquals(lib.hashing.getPackWidth(aliases.Packed), 3)

    local packed = 0
    packed = lib.hashing.writePackedBits(packed, 0, 1, 1)
    packed = lib.hashing.writePackedBits(packed, 1, 2, 3)

    lu.assertEquals(packed, 7)
    lu.assertEquals(lib.hashing.readPackedBits(packed, 0, 1), 1)
    lu.assertEquals(lib.hashing.readPackedBits(packed, 1, 2), 3)

    packed = lib.hashing.writePackedBits(packed, 1, 2, 99)
    lu.assertEquals(lib.hashing.readPackedBits(packed, 1, 2), 3)
end
