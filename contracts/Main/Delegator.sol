// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Storage/StorageMaster.sol";
import "../VerusBridge/Token.sol";

contract Delegator is VerusStorage {
    
    constructor(address[] memory _notaries, address[] memory _notariesEthAddress, address[] memory _notariesColdStoreEthAddress) {
        poolSize = 500000000000;

        for(uint i =0; i < _notaries.length; i++){
            notaryAddressMapping[_notaries[i]] = VerusObjects.notarizer(_notariesEthAddress[i], _notariesColdStoreEthAddress[i], VerusConstants.NOTARY_VALID);
            notaries.push(_notaries[i]);
        }
        VerusNft t = new VerusNft(); 

        verusToERC20mapping[VerusConstants.VerusNFTID] = 
            VerusObjects.mappedToken(address(t), uint8(VerusConstants.MAPPING_VERUS_OWNED + VerusConstants.TOKEN_ETH_NFT_DEFINITION),
                0, "VerusNFT", uint256(0));  

        tokenList.push(VerusConstants.VerusNFTID);
    
    }
    
    receive() external payable {
        
    }

    function submitImports(bytes calldata data) external { 

        bool success;
        bytes memory returnedData;

        address verusBridgeAddress = contracts[uint(VerusConstants.ContractType.CreateExport)];
        (success, returnedData) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("_createImports(bytes)", data));
        require(success);

        uint64 fees = abi.decode(returnedData, (uint64));

        if (fees > 0 ) {
            (success,) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("setClaimableFees(uint64)", fees));
            require(success);
        }
    }

    function getReadyExportsByRange(uint256 _startBlock, uint256 _endBlock) external returns(VerusObjects.CReserveTransferSetCalled[] memory returnedExports){

        address logic = contracts[uint(VerusConstants.ContractType.CreateExport)];

        (bool success, bytes memory returnedData) = logic.delegatecall(abi.encodeWithSignature("getReadyExportsByRange(uint256,uint256)", _startBlock, _endBlock));
        require(success);

        return abi.decode(returnedData, (VerusObjects.CReserveTransferSetCalled[]));
    }
    
    function setLatestData(bytes calldata serializedNotarization, bytes32 txid, uint32 n, bytes calldata data) external {

        address logic = contracts[uint(VerusConstants.ContractType.VerusNotarizer)];

        (bool success, ) = logic.delegatecall(abi.encodeWithSignature("setLatestData(bytes,bytes32,uint32,bytes)", serializedNotarization, txid, n, data));
        require(success);

    }

    function launchContractTokens(bytes calldata data) external  {

        address logic = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];

        (bool success,) = logic.delegatecall(abi.encodeWithSignature("launchContractTokens(bytes)", data));
        require(success);

    }

    function getTokenList(uint256 start, uint256 end) external returns(VerusObjects.setupToken[] memory ) {
        
        address logic = contracts[uint(VerusConstants.ContractType.VerusProof)];

        (bool success, bytes memory returnedData) = logic.delegatecall(abi.encodeWithSignature("getTokenList(uint256,uint256)", start, end));
        require(success);

        return abi.decode(returnedData, (VerusObjects.setupToken[]));

    }

    function checkImport(bytes32 _imports) public view returns(bool){
        return processedTxids[_imports];
    }

    function claimfees() external {
        address submitImportAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];

        (bool success,) = submitImportAddress.delegatecall(abi.encodeWithSignature("claimfees()"));
        require(success);

    }

    function claimRefund(uint176 verusAddress) external {
        address submitImportAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];

        (bool success,) = submitImportAddress.delegatecall(abi.encodeWithSignature("claimRefund(uint176)", verusAddress));
        require(success);

    }

    function sendfees(bytes32 publicKeyX, bytes32 publicKeyY) external {
        address submitImportAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];

        (bool success,) = submitImportAddress.delegatecall(abi.encodeWithSignature("sendfees(bytes32,bytes32)", publicKeyX, publicKeyY));
        require(success);

    } 
    

    function getNewProof(bool latest) public payable returns (bytes memory) {
    }

    function getProofByHeight(uint height) public payable returns (bytes memory) {

       // return verusNotarizer.getProof(height);
    }

    function getProofCost(bool latest) public view returns (uint256) {

      //  return verusNotarizer.getProofCosts(latest);
    }

    function setInitialContracts(address[] memory _newContractAddress) external {

        address upgradeManagerAddress = contracts[uint(VerusConstants.ContractType.UpgradeManager)];

        (bool success,) = upgradeManagerAddress.delegatecall(abi.encodeWithSignature("setInitialContracts(address[])", _newContractAddress));
        require(success);

    }

    function upgradeContracts(bytes calldata data) external returns (uint8) {

        address upgradeManagerAddress = contracts[uint(VerusConstants.ContractType.UpgradeManager)];

        (bool success, bytes memory returnedData) = upgradeManagerAddress.delegatecall(abi.encodeWithSignature("upgradeContracts(bytes)", data));
        require(success);
        
        return abi.decode(returnedData, (uint8));
    }

    function runContractsUpgrade() public returns (uint8) {
      
        address upgradeManagerAddress = contracts[uint(VerusConstants.ContractType.UpgradeManager)];

        (bool success, bytes memory returnedData) = upgradeManagerAddress.delegatecall(abi.encodeWithSignature("runContractsUpgrade()"));
        require(success);
        return abi.decode(returnedData, (uint8));
    }
}