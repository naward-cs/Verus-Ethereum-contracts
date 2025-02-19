// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus
pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "../Storage/StorageMaster.sol";

contract ExportManager is VerusStorage  {

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;
    bool runonce;

    constructor(address vETH, address Bridge, address Verus){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
    }

    function initialize() external {

        _readyExports[18484201].exportHash = 0x2732a5d07110f2d899a8eb2e36f17755cd3ed6ac86ce4c94798454c9078a0b89;
        _readyExports[18484201].transfers[0].secondreserveid = 0x0000000000000000000000000000000000000000;
        _readyExports[18484201].transfers[0].flags = 1;

    }

    uint8 constant UINT160_SIZE = 20; 
    uint8 constant FEE_OFFSET = 20 + 20 + 20 + 8; // 3 x 20bytes address + 64bit uint // 3 x 20bytes address + 64bit uint
    // Aux dest can only be one vector, of one vector which is a CTransferDestiantion of an R address.
    uint8 constant AUX_DEST_LENGTH = 24;

    function ERC20Registered(address _iaddress) private view returns (bool) {

        return verusToERC20mapping[_iaddress].flags > 0;
        
    }

    function checkExport(VerusObjects.CReserveTransfer memory transfer) external payable returns (uint256 fees){
       
        uint256 requiredFees = VerusConstants.transactionFee;  //0.003 eth in WEI (To vrsc) NOTE: convert to VRSC from ETH.
        int64 bounceBackFee;
        int64 transferFee;
        bytes memory serializedDest;
        address gatewayID;
        address gatewayCode;
        address destAddressID;

        require (checkTransferFlags(transfer), "Flag Check failed"); 
 
        serializedDest = transfer.destination.destinationaddress;  
        assembly 
        {
            destAddressID := mload(add(serializedDest, UINT160_SIZE))
        }

        if (verusToERC20mapping[transfer.currencyvalue.currency].flags & (VerusConstants.MAPPING_ERC721_NFT_DEFINITION 
            | VerusConstants.MAPPING_ERC1155_NFT_DEFINITION | VerusConstants.MAPPING_ERC1155_ERC_DEFINITION) != 0) 
        {
            require (transfer.flags == VerusConstants.VALID, "Invalid flags for NFT transfer");
            require (transfer.currencyvalue.amount == 1 
                     || verusToERC20mapping[transfer.currencyvalue.currency].flags & VerusConstants.MAPPING_ERC1155_ERC_DEFINITION 
                     == VerusConstants.MAPPING_ERC1155_ERC_DEFINITION, "Currency value must be 1 Satoshi");
            require (serializedDest.length == VerusConstants.UINT160_SIZE, "destination address not 20 bytes");
        }

        // Check destination address is not zero
        require (destAddressID != address(0), "Destination Address null");
        require (transfer.currencyvalue.currency != transfer.secondreserveid, "Cannot convert like for like");

        if (!bridgeConverterActive) {

            require (transfer.feecurrencyid == VERUS, "feecurrencyid != vrsc");
            
            if (transfer.destination.destinationtype == (VerusConstants.DEST_ETH + VerusConstants.FLAG_DEST_GATEWAY + VerusConstants.FLAG_DEST_AUX) ||
                transfer.flags != VerusConstants.VALID)
                return 0;

            require (transfer.destination.destinationaddress.length == VerusConstants.UINT160_SIZE, "destination address not 20 bytes");

        } else {
            
            transferFee = int64(transfer.fees);

            require(transfer.feecurrencyid == VETH, "Fee Currency not vETH"); //TODO:Accept more fee currencies

            if (transfer.destination.destinationtype == (VerusConstants.FLAG_DEST_GATEWAY + VerusConstants.DEST_ETH + VerusConstants.FLAG_DEST_AUX)) {

                // destinationaddress is concatenated with the gateway back address (bridge.veth) + (gatewayCode) + 0.003 ETH in fees uint64LE
                // destinationaddress is also concatenated with aux dest 
                assembly 
                {
                    gatewayID := mload(add(serializedDest, 40)) // second 20bytes in bytes array
                    gatewayCode := mload(add(serializedDest, 60)) // third 20bytes in bytes array
                    bounceBackFee := mload(add(serializedDest, FEE_OFFSET))
                }

                require (transfer.destination.destinationaddress.length == (FEE_OFFSET + AUX_DEST_LENGTH), "destination address not 68 + 24 bytes");    
                uint32 auxDestPrefix;
                address auxDestAddress;
                
                assembly 
                {
                    auxDestPrefix := mload(add(add(serializedDest, FEE_OFFSET), 4)) // 4bytes AUX_DEST_PREFIX_CONSTANT
                    auxDestAddress := mload(add(add(serializedDest, FEE_OFFSET), 24)) // destaddress
                }
                
                require (auxDestPrefix == VerusConstants.AUX_DEST_PREFIX, "auxDestPrefix Incorrect");
                require (auxDestAddress != address(0), "auxDestAddress must not be empty");
                require (gatewayID == VETH, "GatewayID not VETH");
                require (gatewayCode == address(0), "GatewayCODE must be empty");

                bounceBackFee = reverse(uint64(bounceBackFee));
                //TODO: Change bounce back fee to be the calculated fee.
                require (bounceBackFee >= int64(VerusConstants.verusvETHReturnFee), "Return fee not >= 0.01ETH");

                transferFee += bounceBackFee;
                requiredFees += convertFromVerusNumber(uint64(bounceBackFee),18);  //bounceback fees required as well as send fees

            } else if (!(transfer.destination.destinationtype == VerusConstants.DEST_PKH || transfer.destination.destinationtype == VerusConstants.DEST_ID)) {

                return 0;  

            } 

        }

        // Check fees are included in the ETH value if sending ETH, or are equal to the fee value for tokens.
        uint amount;
        amount = transfer.currencyvalue.amount;

        if (bridgeConverterActive)
        { 
            if (convertFromVerusNumber(uint64(transferFee), 18) < requiredFees)
            {
                revert ("ETH Fees to Low");
            }            
            else if (transfer.currencyvalue.currency == VETH && 
                msg.value < convertFromVerusNumber(uint256(amount + uint64(transferFee)), 18))
            {
                revert ("ETH sent < (amount + fees)");
            } 
            else if (transfer.currencyvalue.currency != VETH &&
                    msg.value < convertFromVerusNumber(uint64(transferFee), 18))
            {
                revert ("ETH fee sent < fees for token");
            } 

            return uint64(transferFee);
        }
        else 
        {
            if (transfer.fees != VerusConstants.verusTransactionFee)
            {
                revert ("Invalid VRSC fee");
            }
            else if (transfer.currencyvalue.currency == VETH &&
                     (convertFromVerusNumber(amount, 18) + requiredFees) != msg.value)
            {
                revert ("ETH Fee to low");
            }
            else if(transfer.currencyvalue.currency != VETH && requiredFees != msg.value)
            {
                revert ("ETH Fee to low (token)");
            }
            claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL]  += VerusConstants.verusvETHTransactionFee;
        } 
        return requiredFees;
    }

    function checkTransferFlags(VerusObjects.CReserveTransfer memory transfer) public view returns(bool) {

        require(transfer.destsystemid == address(0), "currencycheckfailed");

        if (transfer.version != VerusConstants.CURRENT_VERSION || 
            (transfer.flags & (VerusConstants.INVALID_FLAGS | VerusConstants.VALID) ) != VerusConstants.VALID)
        {
            revert ("Invalid Flag used");
        }

        VerusObjects.mappedToken memory sendingCurrency = verusToERC20mapping[transfer.currencyvalue.currency];
        VerusObjects.mappedToken memory destinationCurrency = verusToERC20mapping[transfer.destcurrencyid];

        if (!(transfer.destination.destinationtype == (VerusConstants.DEST_ETH + VerusConstants.FLAG_DEST_GATEWAY + VerusConstants.FLAG_DEST_AUX) || 
                transfer.destination.destinationtype == VerusConstants.DEST_ID ||
                transfer.destination.destinationtype == VerusConstants.DEST_PKH) ||
                sendingCurrency.flags == 0)
        {
            revert ("Invalid desttype");
        }

        if (transfer.flags == VerusConstants.VALID && transfer.secondreserveid == address(0))
        {
            require ((transfer.destcurrencyid == (bridgeConverterActive ? BRIDGE : VERUS) && 
                     (transfer.destination.destinationtype == VerusConstants.DEST_ID ||
                      transfer.destination.destinationtype == VerusConstants.DEST_PKH)),  
                        "Invalid desttype");
        }
        else if (transfer.flags == (VerusConstants.VALID + VerusConstants.CONVERT + VerusConstants.RESERVE_TO_RESERVE))
        {
            require(sendingCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH &&
                    destinationCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY &&
                    verusToERC20mapping[transfer.secondreserveid].flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH,
                        "Cannot convert non bridge reserves");
        }
        else if (transfer.flags == (VerusConstants.VALID + VerusConstants.CONVERT + VerusConstants.IMPORT_TO_SOURCE))
        {
            require(sendingCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY  &&
                    destinationCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH &&
                    transfer.secondreserveid == address(0),
                        "Cannot import non reserve to source");
        }
        else if (transfer.flags == (VerusConstants.VALID + VerusConstants.CONVERT))
        {
            require(sendingCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH  &&
                    destinationCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY &&
                    transfer.secondreserveid == address(0),
                        "Cannot convert non reserve");
        }
        else 
        {
            revert ("Invalid flag combination");
        }

        return true;

    }

    function reverse(uint64 input) public pure returns (int64) 
    {
        // swap bytes
        input = ((input & 0xFF00FF00FF00FF00) >> 8) |
            ((input & 0x00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        input = ((input & 0xFFFF0000FFFF0000) >> 16) |
            ((input & 0x0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        input = (input >> 32) | (input << 32);

        return int64(input);
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