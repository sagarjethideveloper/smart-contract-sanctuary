// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.0;

import "./libraries/TransferHelper.sol";
import "./interfaces/IPremiumPool.sol";

contract PremiumPool is IPremiumPool {
    address private cohort;

    mapping(uint16 => uint256) private _balances; // protocol => premium
    mapping(uint16 => uint256) private _premiumReward; // protocol => total premium reward

    uint256 private _minimumPremium;
    address public override currency;

    event PremiumDeposited(uint16 indexed protocolIdx, uint256 amount);
    event TransferAsset(address indexed _to, uint256 _amount);

    constructor(
        address _cohort,
        address _currency,
        uint256 _minimum
    ) {
        cohort = _cohort;
        currency = _currency;
        _minimumPremium = _minimum;
    }

    modifier onlyCohort() {
        require(msg.sender == cohort, "UnoRe: Not cohort");
        _;
    }

    function balanceOf(uint16 _protocolIdx) external view override returns (uint256) {
        return _balances[_protocolIdx];
    }

    function premiumRewardOf(uint16 _protocolIdx) external override onlyCohort returns (uint256) {
        if (_premiumReward[_protocolIdx] == 0) {
            _premiumReward[_protocolIdx] = _balances[_protocolIdx];
        }
        return _premiumReward[_protocolIdx];
    }

    function minimumPremium() external view override returns (uint256) {
        return _minimumPremium;
    }

    function depositPremium(uint16 _protocolIdx, uint256 _amount) external override onlyCohort {
        _balances[_protocolIdx] += _amount;
        emit PremiumDeposited(_protocolIdx, _amount);
    }

    function withdrawPremium(
        address _to,
        uint16 _protocolIdx,
        uint256 _amount
    ) external override onlyCohort {
        require(_balances[_protocolIdx] >= _amount, "UnoRe: Insufficient Premium");
        _balances[_protocolIdx] -= _amount;
        TransferHelper.safeTransfer(currency, _to, _amount);
    }

    function transferAsset(
        uint16 _protocolIdx,
        address _to,
        uint256 _amount
    ) external override onlyCohort {
        _balances[_protocolIdx] -= _amount;
        TransferHelper.safeTransfer(currency, _to, _amount);
        emit TransferAsset(_to, _amount);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.0;

interface IPremiumPool {
    function depositPremium(uint16 _protocolIdx, uint256 _amount) external;

    function withdrawPremium(
        address _to,
        uint16 _protocolIdx,
        uint256 _amount
    ) external;

    function transferAsset(
        uint16 _protocolIdx,
        address _to,
        uint256 _amount
    ) external;

    function minimumPremium() external returns (uint256);

    function balanceOf(uint16 _protocolIdx) external view returns (uint256);

    function premiumRewardOf(uint16 _protocolIdx) external returns (uint256);

    function currency() external view returns (address);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.0;

// from Uniswap TransferHelper library
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper::safeApprove: approve failed");
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper::safeTransfer: transfer failed");
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferHelper::transferFrom: transferFrom failed");
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper::safeTransferETH: ETH transfer failed");
    }
}

