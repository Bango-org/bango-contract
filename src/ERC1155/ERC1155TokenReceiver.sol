// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC1155//IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {SupportsInterfaceWithLookupMock} from "@openzeppelin/contracts/mocks/ERC165/ERC165InterfacesSupported.sol";


contract ERC1155TokenReceiver is IERC1155Receiver, SupportsInterfaceWithLookupMock {

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {


    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {

    }
}