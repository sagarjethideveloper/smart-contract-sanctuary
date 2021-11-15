// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract CyBlocGeneScientist {
    uint256 public bitClass = 3;
    uint256 public bitTrait = 5;
    uint256 public numOfTraits = 3;
    function validateGene(uint256 gene) public pure returns (bool) {
        return gene > 0;
    }

    function generateGene(uint256 class, uint256[3] memory traits) public pure returns (uint256) {
        return class + traits.length;
    }

    function parseGene(uint256 gene) public pure returns (uint256 class, uint256[3] memory traits) {
        return (gene, [uint256(0), uint256(0), uint256(0)]);
    }

    function mixGenes(uint256[2] memory genes, uint256 randomNumber) public pure returns (uint256) {
        return genes[0] + genes[1] + randomNumber;
    }

    function setNumOfTrait(uint256 _numOfTraits) public  {
        numOfTraits = _numOfTraits;
    }    

    function setBitClass(uint256 _bitClass) public  {
        bitClass = _bitClass;
    }    

    function setBitTrait(uint256 _bitTrait) public  {
        bitTrait = _bitTrait;
    }       

    function decode(uint256 _genes) public view returns(uint256 class, uint256 trait, uint256 _class, uint256 _trait,uint8[] memory _classs) {
        uint8[] memory traits = new uint8[](20);
        uint8[] memory classs = new uint8[](2);

         _class = _sliceNumber(_genes, 3,  0); 
         _trait = _sliceNumber(_genes, 5, 0);  

        uint256 i;
        for(i = 0; i < 20; i++) {
            traits[i] = _getnBits(_trait, i, bitTrait);
        }

        uint256 j;
        for(j = 0; j < 2; j++) {
            classs[j] = _getnBits(_class, j, bitClass);
        }
        trait = encode(traits, 20, bitTrait);  
        class = encode(classs, 2, bitClass);  
        _classs = classs;
    }

    function _getnBits(uint256 _input, uint256 _slot, uint256 _numOfBits) internal view returns(uint8) {
        return uint8(_sliceNumber(_input, uint256(_numOfBits), _slot * _numOfBits));
    } 

    function _sliceNumber(uint256 _n, uint256 _nbits, uint256 _offset) private view returns (uint256) {
        // mask is made by shifting left an offset number of times
        uint256 mask = uint256((2**_nbits) - 1) << _offset;
        // AND n with mask, and trim to max of _nbits bits
        return uint256((_n & mask) >> _offset);
    }  

    function encode(uint8[] memory _traits, uint256 _numOfDigi, uint256 _numOfBits) public view returns (uint256 _genes) {
        _genes = 0;
        for(uint256 i = 0; i < _numOfDigi; i++) {
            _genes = _genes << _numOfBits;
            // bitwise OR trait with _genes
            _genes = _genes | _traits[(_numOfDigi - 1) - i];
        }
        return _genes;
    }
}

