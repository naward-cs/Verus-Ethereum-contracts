// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "./Token.sol";
import "../Storage/StorageMaster.sol";
import "./ExportManager.sol";
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

contract CreateExports is VerusStorage {

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;

    constructor(address vETH, address Bridge, address Verus){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
    }

    function subtractPoolSize(uint64 _amount) private returns (bool) {

        if((_amount + VerusConstants.MIN_VRSC_FEE) > remainingLaunchFeeReserves) return false;
        remainingLaunchFeeReserves -= _amount;
        return true;
    }

    function sendTransfer(bytes calldata datain) payable external {

        VerusObjects.CReserveTransfer memory transfer = abi.decode(datain, (VerusObjects.CReserveTransfer));        
        sendTransferMain(transfer);
    }

    function sendTransferDirect(bytes calldata datain) payable external {

        address serializerAddress = contracts[uint(VerusConstants.ContractType.VerusSerializer)];

        (bool success, bytes memory returnData) = serializerAddress.call(abi.encodeWithSignature("deserializeTransfer(bytes)",datain));

        require(success, "deserializetransfer failed");  

        VerusObjects.CReserveTransfer memory transfer = abi.decode(returnData, (VerusObjects.CReserveTransfer));
        sendTransferMain(transfer);
    }
 
    function sendTransferMain(VerusObjects.CReserveTransfer memory transfer) private {

        uint256 fees;
        VerusObjects.mappedToken memory mappedContract;
        uint32 ethNftFlag;
        address verusExportManagerAddress = contracts[uint(VerusConstants.ContractType.ExportManager)];

        (bool success, bytes memory returnData) = verusExportManagerAddress.delegatecall(abi.encodeWithSelector(ExportManager.checkExport.selector, transfer));
        require(success, "checkExport call failed");

        fees = abi.decode(returnData, (uint256)); 

        require(fees != 0, "CheckExport Failed Checks"); 

        if(!bridgeConverterActive) {
            require (subtractPoolSize(uint64(transfer.fees)));
        }

        if (transfer.currencyvalue.currency != VETH) {
            mappedContract = verusToERC20mapping[transfer.currencyvalue.currency];
            ethNftFlag = mappedContract.flags & (VerusConstants.MAPPING_ERC721_NFT_DEFINITION | VerusConstants.MAPPING_ERC1155_NFT_DEFINITION | VerusConstants.MAPPING_ERC1155_ERC_DEFINITION);
        }

        if (ethNftFlag != 0) { //handle a NFT Import

            if (ethNftFlag == VerusConstants.MAPPING_ERC1155_NFT_DEFINITION || ethNftFlag == VerusConstants.MAPPING_ERC1155_ERC_DEFINITION) {
                IERC1155 nft = IERC1155(mappedContract.erc20ContractAddress);

                // TokenIndex is used for ERC1155's only for the amount of tokens held by the bridge
                require((transfer.currencyvalue.amount + mappedContract.tokenIndex) < VerusConstants.MAX_VERUS_TRANSFER);
                verusToERC20mapping[transfer.currencyvalue.currency].tokenIndex += transfer.currencyvalue.amount;

                if (contracts.length == VerusConstants.NUMBER_OF_CONTRACTS) {
                    require (nft.isApprovedForAll(msg.sender, address(this)), "NFT not approved");
                     nft.safeTransferFrom(msg.sender, address(this), mappedContract.tokenID, transfer.currencyvalue.amount, ""); 
                } else {
                    require (nft.isApprovedForAll(msg.sender, contracts[uint160(VerusConstants.ContractType.NFTHolder)]), "NFT not approved");
                    (bool Nftsuccess,) = contracts[uint160(VerusConstants.ContractType.NFTHolder)].call(abi.encodeWithSignature("getERC1155(address,address,uint256,uint256)", mappedContract.erc20ContractAddress, msg.sender, mappedContract.tokenID, uint256(transfer.currencyvalue.amount)));
                    require (Nftsuccess);
                }

            } else if (ethNftFlag == VerusConstants.MAPPING_ERC721_NFT_DEFINITION){
                VerusNft nft = VerusNft(mappedContract.erc20ContractAddress);
                require (nft.getApproved(mappedContract.tokenID) == address(this), "NFT not approved");
                nft.safeTransferFrom(msg.sender, address(this), mappedContract.tokenID, "");

                if (transfer.currencyvalue.currency == verusToERC20mapping[tokenList[VerusConstants.NFT_POSITION]].erc20ContractAddress) {
                    nft.burn(mappedContract.tokenID);
                }
            } else {
                revert();
            }
         } else if (transfer.currencyvalue.currency != VETH) {

            Token token = Token(mappedContract.erc20ContractAddress); 
            //Check user has allowed the verusBridgeStorage contract to spend on their behalf
            uint256 allowedTokens = token.allowance(msg.sender, address(this));
            uint256 tokenAmount = convertFromVerusNumber(transfer.currencyvalue.amount, token.decimals()); //convert to wei from verus satoshis
            if (mappedContract.flags & VerusConstants.MAPPING_ETHEREUM_OWNED == VerusConstants.MAPPING_ETHEREUM_OWNED) {
                // TokenID is used for ERC20's only for the amount of tokens held by the bridge
                require((transfer.currencyvalue.amount + mappedContract.tokenID) < VerusConstants.MAX_VERUS_TRANSFER);
                verusToERC20mapping[transfer.currencyvalue.currency].tokenID += transfer.currencyvalue.amount;

            }
            require( allowedTokens >= tokenAmount);
            //transfer the tokens to the delegator contract
            //total amount kept as uint256 until export to verus
            exportERC20Tokens(tokenAmount, token, mappedContract.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED);
            
        } else if(transfer.currencyvalue.currency != VETH) {
            revert ("unknown type");
        }
        _createExports(transfer, false);
    }

    function exportERC20Tokens(uint256 _tokenAmount, Token token, bool burn) private {
        
        (bool success, ) = address(token).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), _tokenAmount));
        require(success, "transferfrom of token failed");

        if (burn) 
        {
            token.burn(_tokenAmount);
        }
    }

    function externalCreateExportCall(bytes memory data) public {

        (VerusObjects.CReserveTransfer memory reserveTransfer, bool forceNewCCE) = abi.decode(data, (VerusObjects.CReserveTransfer, bool));

        _createExports(reserveTransfer, forceNewCCE);
    }

    function _createExports(VerusObjects.CReserveTransfer memory reserveTransfer, bool forceNewCCE) private {

        // If transactions over 50 and inbetween notarization boundaries, increment CCE start and endheight
        // If notarization has happened increment CCE to next boundary when the tx comes in
        // If changing from pool closed to pool open create a boundary (As all sends will then go through the bridge)
        uint64 blockNumber = uint64(block.number);
        uint64 blockDelta = blockNumber - cceLastStartHeight;
        uint64 lastTransfersLength = uint64(_readyExports[cceLastStartHeight].transfers.length);
        bytes32 prevHash = _readyExports[cceLastStartHeight].exportHash;
        // if there are no transfers then there is no need to make a new CCE as this is the first one, and the endheight can become the block number if it is less than the current block no.
        // if the last notary received height is less than the endheight then keep building up the CCE (as long as 10 ETH blocks havent passed, and a new CCE isnt being forced and there is less than 50)

        if ((cceLastEndHeight == 0 || blockDelta < 10) && !forceNewCCE  && lastTransfersLength < 50) {

            // set the end height of the CCE to the current block.number only if the current block we are on is greater than its value
            if (cceLastEndHeight < blockNumber) {
                cceLastEndHeight = blockNumber;
            }
        // if a new CCE is triggered for any reason, its startblock is always the previous endblock +1, 
        // its start height may of spilled in to virtual future block numbers so if the current cce start height is less than the block we are on we can update the end 
        // height to a new greater value.  Otherwise if the startheight is still in the future then the endheight is also in the future at the same block.
        } else {
            cceLastStartHeight = cceLastEndHeight + 1;

            if (cceLastStartHeight < blockNumber) {
                cceLastEndHeight = blockNumber;
            } else {
                cceLastEndHeight = cceLastStartHeight;
            }
        }

        if (exportHeights[cceLastEndHeight] != cceLastStartHeight) {
            exportHeights[cceLastEndHeight] = cceLastStartHeight;
        }

        setReadyExportTransfers(cceLastStartHeight, cceLastEndHeight, reserveTransfer, 50);
        VerusObjects.CReserveTransferSet memory pendingTransfers = _readyExports[cceLastStartHeight];
        address crossChainExportAddress = contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)];

        (bool success, bytes memory returnData) = crossChainExportAddress.call(abi.encodeWithSignature("generateCCE(bytes)", abi.encode(pendingTransfers.transfers, bridgeConverterActive, cceLastStartHeight, cceLastEndHeight, contracts[uint(VerusConstants.ContractType.VerusSerializer)])));
        require(success, "generateCCEfailed");

        bytes memory serializedCCE = abi.decode(returnData, (bytes)); 

        if(pendingTransfers.transfers.length > 1)
        {
            prevHash = pendingTransfers.prevExportHash;
        }
        setReadyExportTxid(keccak256(abi.encodePacked(serializedCCE, prevHash)), prevHash, cceLastStartHeight);

    }

    function setReadyExportTxid(bytes32 txidhash, bytes32 prevTxidHash, uint _block) private {
        
        _readyExports[_block].exportHash = txidhash;

        if (_readyExports[_block].transfers.length == 1)
        {
            _readyExports[_block].prevExportHash = prevTxidHash;

        }
    }

    function setReadyExportTransfers(uint64 _startHeight, uint64 _endHeight, VerusObjects.CReserveTransfer memory reserveTransfer, uint blockTxLimit) private {
        
        _readyExports[_startHeight].endHeight = _endHeight;
        _readyExports[_startHeight].transfers.push(reserveTransfer);
        require(_readyExports[_startHeight].transfers.length <= blockTxLimit);
      
    }
        
    function convertFromVerusNumber(uint256 a,uint8 decimals) public pure returns (uint256) {
        uint8 power = 10; //default value for 18
        uint256 c = a;

        if(decimals > 8 ) {
            power = decimals - 8;// number of decimals in verus
            c = a * (10 ** power);
        }else if(decimals < 8){
            power = 8 - decimals;// number of decimals in verus
            c = a / (10 ** power);
        }
      
        return c;
    }
}
