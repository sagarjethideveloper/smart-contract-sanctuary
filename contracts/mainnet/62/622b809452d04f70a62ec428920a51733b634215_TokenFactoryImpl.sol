/*
  Copyright 2017 Loopring Project Ltd (Loopring Foundation).
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
pragma solidity 0.4.21;
/// @title Utility Functions for address
/// @author Kongliang Zhong - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="c9a2a6a7aea5a0a8a7ae89a5a6a6b9bba0a7aee7a6bbae">[email&#160;protected]</a>>
library StringUtil {
    function stringToBytes12(string str)
        internal
        pure
        returns (bytes12 result)
    {
        assembly {
            result := mload(add(str, 32))
        }
    }
    function stringToBytes10(string str)
        internal
        pure
        returns (bytes10 result)
    {
        assembly {
            result := mload(add(str, 32))
        }
    }
    /// check length >= min && <= max
    function checkStringLength(string name, uint min, uint max)
        internal
        pure
        returns (bool)
    {
        bytes memory temp = bytes(name);
        return temp.length >= min && temp.length <= max;
    }
}
/*
  Copyright 2017 Loopring Project Ltd (Loopring Foundation).
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/// @title Utility Functions for address
/// @author Daniel Wang - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="284c4946414d4468444747585a41464f06475a4f">[email&#160;protected]</a>>
library AddressUtil {
    function isContract(
        address addr
        )
        internal
        view
        returns (bool)
    {
        if (addr == 0x0) {
            return false;
        } else {
            uint size;
            assembly { size := extcodesize(addr) }
            return size > 0;
        }
    }
}
/*
  Copyright 2017 Loopring Project Ltd (Loopring Foundation).
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/*
    Copyright 2017 Loopring Project Ltd (Loopring Foundation).
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/
/*
  Copyright 2017 Loopring Project Ltd (Loopring Foundation).
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/// @title ERC20 Token Interface
/// @dev see https://github.com/ethereum/EIPs/issues/20
/// @author Daniel Wang - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="6f0b0e01060a032f0300001f1d06010841001d08">[email&#160;protected]</a>>
contract ERC20 {
    function balanceOf(
        address who
        )
        view
        public
        returns (uint256);
    function allowance(
        address owner,
        address spender
        )
        view
        public
        returns (uint256);
    function transfer(
        address to,
        uint256 value
        )
        public
        returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 value
        )
        public
        returns (bool);
    function approve(
        address spender,
        uint256 value
        )
        public
        returns (bool);
}
/*
  Copyright 2017 Loopring Project Ltd (Loopring Foundation).
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/// @title Utility Functions for uint
/// @author Daniel Wang - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="1a7e7b74737f765a7675756a6873747d3475687d">[email&#160;protected]</a>>
library MathUint {
    function mul(
        uint a,
        uint b
        )
        internal
        pure
        returns (uint c)
    {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    function sub(
        uint a,
        uint b
        )
        internal
        pure
        returns (uint)
    {
        require(b <= a);
        return a - b;
    }
    function add(
        uint a,
        uint b
        )
        internal
        pure
        returns (uint c)
    {
        c = a + b;
        require(c >= a);
    }
    function tolerantSub(
        uint a,
        uint b
        )
        internal
        pure
        returns (uint c)
    {
        return (a >= b) ? a - b : 0;
    }
    /// @dev calculate the square of Coefficient of Variation (CV)
    /// https://en.wikipedia.org/wiki/Coefficient_of_variation
    function cvsquare(
        uint[] arr,
        uint scale
        )
        internal
        pure
        returns (uint)
    {
        uint len = arr.length;
        require(len > 1);
        require(scale > 0);
        uint avg = 0;
        for (uint i = 0; i < len; i++) {
            avg += arr[i];
        }
        avg = avg / len;
        if (avg == 0) {
            return 0;
        }
        uint cvs = 0;
        uint s;
        uint item;
        for (i = 0; i < len; i++) {
            item = arr[i];
            s = item > avg ? item - avg : avg - item;
            cvs += mul(s, s);
        }
        return ((mul(mul(cvs, scale), scale) / avg) / avg) / (len - 1);
    }
}
/// @title ERC20 Token Implementation
/// @dev see https://github.com/ethereum/EIPs/issues/20
/// @author Daniel Wang - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="0367626d6a666f436f6c6c73716a6d642d6c7164">[email&#160;protected]</a>>
contract ERC20Token is ERC20 {
    using MathUint for uint;
    string  public name;
    string  public symbol;
    uint8   public decimals;
    uint    public totalSupply_;
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) internal allowed;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function ERC20Token(
        string  _name,
        string  _symbol,
        uint8   _decimals,
        uint    _totalSupply,
        address _firstHolder
        )
        public
    {
        require(_totalSupply > 0);
        require(_firstHolder != 0x0);
        checkSymbolAndName(_symbol,_name);
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply_ = _totalSupply;
        balances[_firstHolder] = totalSupply_;
    }
    function ()
        payable
        public
    {
        revert();
    }
    /**
    * @dev total number of tokens in existence
    */
    function totalSupply()
        public
        view
        returns (uint256)
    {
        return totalSupply_;
    }
    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(
        address _to,
        uint256 _value
        )
        public
        returns (bool)
    {
        require(_to != address(0));
        require(_value <= balances[msg.sender]);
        // SafeMath.sub will throw if there is not enough balance.
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function balanceOf(
        address _owner
        )
        public
        view
        returns (uint256 balance)
    {
        return balances[_owner];
    }
    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
        )
        public
        returns (bool)
    {
        require(_to != address(0));
        require(_value <= balances[_from]);
        require(_value <= allowed[_from][msg.sender]);
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }
    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     *
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender&#39;s allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(
        address _spender,
        uint256 _value
        )
        public
        returns (bool)
    {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param _spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(
        address _owner,
        address _spender
        )
        public
        view
        returns (uint256)
    {
        return allowed[_owner][_spender];
    }
    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     *
     * approve should be called when allowed[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseApproval(
        address _spender,
        uint _addedValue
        )
        public
        returns (bool)
    {
        allowed[msg.sender][_spender] = allowed[msg.sender][_spender].add(_addedValue);
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }
    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     *
     * approve should be called when allowed[_spender] == 0. To decrement
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseApproval(
        address _spender,
        uint _subtractedValue
        )
        public
        returns (bool)
    {
        uint oldValue = allowed[msg.sender][_spender];
        if (_subtractedValue > oldValue) {
            allowed[msg.sender][_spender] = 0;
        } else {
            allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }
    // Make sure symbol has 3-8 chars in [A-Za-z._] and name has up to 128 chars.
    function checkSymbolAndName(
        string memory _symbol,
        string memory _name
        )
        internal
        pure
    {
        bytes memory s = bytes(_symbol);
        require(s.length >= 3 && s.length <= 8);
        for (uint i = 0; i < s.length; i++) {
            require(
                s[i] == 0x2E ||  // "."
                s[i] == 0x5F ||  // "_"
                s[i] >= 0x41 && s[i] <= 0x5A ||  // [A-Z]
                s[i] >= 0x61 && s[i] <= 0x7A     // [a-z]
            );
        }
        bytes memory n = bytes(_name);
        require(n.length >= s.length && n.length <= 128);
        for (i = 0; i < n.length; i++) {
            require(n[i] >= 0x20 && n[i] <= 0x7E);
        }
    }
}
/*
  Copyright 2017 Loopring Project Ltd (Loopring Foundation).
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/// @title ERC20 Token Mint
/// @dev This contract deploys ERC20 token contract and registered the contract
///      so the token can be traded with Loopring Protocol.
/// @author Kongliang Zhong - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="583337363f343139363f18343737282a31363f76372a3f">[email&#160;protected]</a>>,
/// @author Daniel Wang - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="0367626d6a666f436f6c6c73716a6d642d6c7164">[email&#160;protected]</a>>.
contract TokenFactory {
    event TokenCreated(
        address indexed addr,
        string  name,
        string  symbol,
        uint8   decimals,
        uint    totalSupply,
        address firstHolder
    );
    /// @dev Deploy an ERC20 token contract, register it with TokenRegistry,
    ///      and returns the new token&#39;s address.
    /// @param name The name of the token
    /// @param symbol The symbol of the token.
    /// @param decimals The decimals of the token.
    /// @param totalSupply The total supply of the token.
    function createToken(
        string  name,
        string  symbol,
        uint8   decimals,
        uint    totalSupply
        )
        external
        returns (address addr);
}
/*
  Copyright 2017 Loopring Project Ltd (Loopring Foundation).
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/// @title Token Register Contract
/// @dev This contract maintains a list of tokens the Protocol supports.
/// @author Kongliang Zhong - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="214a4e4f464d48404f46614d4e4e5153484f460f4e5346">[email&#160;protected]</a>>,
/// @author Daniel Wang - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="c1a5a0afa8a4ad81adaeaeb1b3a8afa6efaeb3a6">[email&#160;protected]</a>>.
contract TokenRegistry {
    event TokenRegistered(address addr, string symbol);
    event TokenUnregistered(address addr, string symbol);
    function registerToken(
        address addr,
        string  symbol
        )
        external;
    function registerMintedToken(
        address addr,
        string  symbol
        )
        external;
    function unregisterToken(
        address addr,
        string  symbol
        )
        external;
    function areAllTokensRegistered(
        address[] addressList
        )
        external
        view
        returns (bool);
    function getAddressBySymbol(
        string symbol
        )
        external
        view
        returns (address);
    function isTokenRegisteredBySymbol(
        string symbol
        )
        public
        view
        returns (bool);
    function isTokenRegistered(
        address addr
        )
        public
        view
        returns (bool);
    function getTokens(
        uint start,
        uint count
        )
        public
        view
        returns (address[] addressList);
}
/// @title An Implementation of TokenFactory.
/// @author Kongliang Zhong - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="b4dfdbdad3d8ddd5dad3f4d8dbdbc4c6dddad39adbc6d3">[email&#160;protected]</a>>,
/// @author Daniel Wang - <<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="7115101f18141d311d1e1e0103181f165f1e0316">[email&#160;protected]</a>>.
contract TokenFactoryImpl is TokenFactory {
    using AddressUtil for address;
    using StringUtil for string;
    mapping(bytes10 => address) public tokens;
    address   public tokenRegistry;
    address   public tokenTransferDelegate;
    /// @dev Disable default function.
    function ()
        payable
        public
    {
        revert();
    }
    function TokenFactoryImpl(
        address _tokenRegistry
        )
        public
    {
        require(tokenRegistry == 0x0 && _tokenRegistry.isContract());
        tokenRegistry = _tokenRegistry;
    }
    function createToken(
        string  name,
        string  symbol,
        uint8   decimals,
        uint    totalSupply
        )
        external
        returns (address addr)
    {
        require(tokenRegistry != 0x0);
        require(tokenTransferDelegate != 0x0);
        require(symbol.checkStringLength(3, 10));
        bytes10 symbolBytes = symbol.stringToBytes10();
        require(tokens[symbolBytes] == 0x0);
        ERC20Token token = new ERC20Token(
            name,
            symbol,
            decimals,
            totalSupply,
            tx.origin
        );
        addr = address(token);
        TokenRegistry(tokenRegistry).registerMintedToken(addr, symbol);
        tokens[symbolBytes] = addr;
        emit TokenCreated(
            addr,
            name,
            symbol,
            decimals,
            totalSupply,
            tx.origin
        );
    }
}