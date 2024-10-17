// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IndexerRole
 * @dev Contract module that defines an Indexer with exclusive access to specific functions.
 */
contract IndexerRole is Ownable {
    mapping(address => bool) public isIndexer;

    event IndexerAdded(address indexed account);
    event IndexerRemoved(address indexed account);

    constructor() Ownable(tx.origin) {}

    /**
     * @dev Modifier to restrict access to Indexers.
     */
    modifier onlyIndexer() {
        require(isIndexer[msg.sender], "IndexerRole: caller does not have the Indexer role");
        _;
    }

    /**
     * @dev Adds an account to the Indexer role.
     * Can only be called by the owner.
     * @param account The address to assign the Indexer role.
     */
    function addIndexer(address account) external onlyOwner {
        require(account != address(0), "IndexerRole: account is the zero address");
        require(!isIndexer[account], "IndexerRole: account already an indexer");
        isIndexer[account] = true;
        emit IndexerAdded(account);
    }

    /**
     * @dev Removes an account from the Indexer role.
     * Can only be called by the owner.
     * @param account The address to remove from the Indexer role.
     */
    function removeIndexer(address account) external onlyOwner {
        require(isIndexer[account], "IndexerRole: account is not an indexer");
        isIndexer[account] = false;
        emit IndexerRemoved(account);
    }
}
