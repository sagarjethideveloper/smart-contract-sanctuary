// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

library BuddyLib {
    struct Buddy {
        uint8 species;
        uint8[30] traits;
        uint8 gen;
        uint8 repMax;
        uint8 repCur;
        bool founder;
        uint256 dna;
        uint256 birth;
        uint256 totalProduced;
        uint256 lastRewardBlock;
        uint256 lastFounderClaim;
        uint256 lastFounderClaimBlock;
    }

    function generate(uint256 dna) external view returns (Buddy memory base) {
        uint8[] memory unpack = decode(dna);
        base.species = unpack[0];

        for (uint8 i = 1; i < 31; i++) {
            base.traits[i - 1] = unpack[i];
        }

        base.birth = block.number;
        base.totalProduced = 0;
        base.lastRewardBlock = block.number;
        base.dna = dna;
        base.gen = unpack[31];
        base.repMax = 5;
        base.repCur = 0;

        return base;
    }

    function decode(uint256 dna) public pure returns (uint8[] memory) {
        uint8[] memory traits = new uint8[](32);
        uint256 i;
        for (i = 0; i < 32; i++) {
            traits[i] = uint8(sliceNumber(dna, 8, i * 8));
        }
        return traits;
    }

    /// @dev given a number get a slice of any bits, at certain offset
    /// @param _n a number to be sliced
    /// @param _nbits how many bits long is the new number
    /// @param _offset how many bits to skip
    function sliceNumber(
        uint256 _n,
        uint256 _nbits,
        uint256 _offset
    ) public pure returns (uint256) {
        // mask is made by shifting left an offset number of times
        uint256 mask = (pow(2, _nbits) - 1) << _offset;
        // AND n with mask, and trim to max of _nbits bits
        return uint256((_n & mask) >> _offset);
    }

    function pow(uint256 A, uint256 B) public pure returns (uint256) {
        return A**B;
    }

    function encode(uint8[] memory traits) external pure returns (uint256 dna) {
        dna = 0;
        for (uint256 i = 0; i < 32; i++) {
            dna = dna << 8;
            // bitwise OR trait with _genes
            dna = dna | traits[31 - i];
        }
    }
}

