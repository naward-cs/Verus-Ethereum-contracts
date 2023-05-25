// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../VerusBridge/Token.sol";
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";


contract VerusStorage {

    //verusbridgestorage
    mapping (uint => VerusObjects.CReserveTransferSet) public _readyExports;
    mapping (uint => uint) public exportHeights;

    mapping (bytes32 => bool) public processedTxids;
    mapping (address => VerusObjects.mappedToken) public verusToERC20mapping;
    mapping (bytes32 => VerusObjects.lastImportInfo) public lastImportInfo;

    address[] public tokenList;
    bytes32 public lastTxIdImport;

    uint64 public cceLastStartHeight;
    uint64 public cceLastEndHeight;

    //verusnotarizer storage

    bool public poolAvailable;
    mapping (bytes32 => bytes) public storageGlobal;    // Generic storage location
    mapping (bytes32 => bytes) internal proofs;         // Stored Verus stateroot/blockhash proofs indexed by height.
    mapping (bytes32 => uint256) public claimableFees;  // CreserveTRansfer destinations mapped to Fees they have accrued.
    mapping (bytes32 => uint256) public refunds;        // Failed transaction refunds 

    uint64 poolSize;   // Starts at 5000 VRSC

    //upgrademanager
    address[] public contracts;  // List of all known contracts Delegator trusts to use (contracts replacable on upgrade)

    mapping (address => VerusObjects.voteState) public pendingVoteState; // Potential contract upgrades

    mapping (bytes32 => bool) public saltsUsed;   //salts used for upgrades and revoking.

    // verusnotarizer
    
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping; // Mapping iaddress of notaries to their spend/recover ETH addresses
    mapping (bytes32 => bool) knownNotarizationTxids;

    address[] public notaries; // Notaries for enumeration

    bytes[] public bestForks; // Forks array

    address public owner;    // TEestnet only owner to allow quick upgrades, TODO: Remove once Voting established.

    uint64 public lastRecievedGasPrice;  //Gasprice last recieved.
}