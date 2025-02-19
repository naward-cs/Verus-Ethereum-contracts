const VerusDelegator = artifacts.require("../contracts/Main/Delegator.sol");
const VerusSerializer = artifacts.require("../contracts/VerusBridge/VerusSerializer.sol");
const { getNotarizerIDS } = require('../migrations/setup.js')
const verusDelegatorAbi = require('../build/contracts/Delegator.json');
const verusSerializerAbi = require('../build/contracts/VerusSerializer.json');
const testNotarization = require('./submitnotarization.js')
const reservetransfer = require('./reservetransfer.ts')
const { toBase58Check } = require("verus-typescript-primitives");
const ERC721 = require("../build/contracts/ERC721.json");

contract("Verus Contracts deployed tests", async(accounts)  => {
    
    it("All 6 Currencies Deployed", async() => {
        const DelegatorInst = await VerusDelegator.deployed();
        let tokensList = await DelegatorInst.getTokenList.call(0,0);
        assert.equal(tokensList.length, 6, "Not all currencies were deployed");
    });

    it("Notaries Deployed", async() => {
        const DelegatorInst = await VerusDelegator.deployed();

        const notaries = getNotarizerIDS("development")[0]

        for (let i=0; i< notaries.length; i++){

            let firstnotary = await DelegatorInst.notaries.call(i);
            assert.equal(firstnotary.toLowerCase(), notaries[i].toLowerCase());

        }
        assert.ok(true);
    });

    it("Send 1 ETH to Contract", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;
    
        // Get the contract balance before sending ETH
        const initialBalance = await web3.eth.getBalance(contractAddress);
    
        // Send 1 ETH to the contract
        const sendAmount = web3.utils.toWei("1", "ether");
        await web3.eth.sendTransaction({ from: accounts[0], to: contractAddress, value: sendAmount });
    
        // Get the contract balance after sending ETH
        const finalBalance = await web3.eth.getBalance(contractAddress);
    
        // Check if the contract balance increased by 1 ETH
        const expectedBalance = web3.utils.toBN(initialBalance).add(web3.utils.toBN(sendAmount));
        assert.equal(finalBalance.toString(), expectedBalance.toString(), "Contract balance is incorrect after sending ETH");
      });

      it("Send 1 ETH in Serialized ReserveTransfer to Contract", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;

        const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);
  
    
        // Send 1 ETH to the contract
        const sendAmount = web3.utils.toWei("1.003", "ether");
        const serializedTx = `0x${reservetransfer.prelaunchfundETH.toBuffer().toString('hex')}`;
        //console.log("reservetransfer transaction " + JSON.stringify(reservetransfer, null, 2))
        let reply
        try {
            reply = await contractInstance.methods.sendTransferDirect(serializedTx).send({ from: accounts[0], gas: 6000000, value: sendAmount }); 
            // Get the contract balance after sending ETH exportHeights
            const previousStartHeight = await DelegatorInst.exportHeights.call(0);
            let reserveimport = await DelegatorInst.getReadyExportsByRange.call(0, reply.blockNumber + 10);
        
          assert.equal(reply.blockNumber, reserveimport[0].endHeight, "Endheight should equal insertion height");
        } catch(e) {
            console.log(e.message)
            assert.ok(false);
        }

      });

      it("Send 2 ETH in ReserveTransfer to Contract", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;
        const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);
        // Send 1 ETH to the contract
        const sendAmount = web3.utils.toWei("2.003", "ether");

        const CReserveTransfer = {
            version: 1,
            currencyvalue: { currency: "0x67460C2f56774eD27EeB8685f29f6CEC0B090B00", amount: 200000000 }, // currency sending from ethereum
            flags: 1,
            feecurrencyid: "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", // fee is vrsctest pre bridge launch, veth or others post.
            fees: 2000000,
            destination: { destinationtype: 2, destinationaddress: "0x9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD" }, // destination address currecny is going to
            destcurrencyid: "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d",   // destination currency is vrsc on direct. bridge.veth on bounceback
            destsystemid: "0x0000000000000000000000000000000000000000",     // destination system not used 
            secondreserveid: "0x0000000000000000000000000000000000000000"    // used as return currency type on bounce back
          }
        let reply
        try {
            reply = await contractInstance.methods.sendTransfer(CReserveTransfer).send({ from: accounts[0], gas: 6000000, value: sendAmount }); 
        } catch(e) {
            console.log(e)
            assert.isTrue(false);
        }
        // Get the contract balance after sending ETH exportHeights
        const previousStartHeight = await DelegatorInst.exportHeights.call(0);
        let reserveimport = await DelegatorInst.getReadyExportsByRange.call(0, reply.blockNumber + 10);
        assert.isTrue(true);
      });

      it("Submit accepeted notarization by Notary", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;
        const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);

        let reply;
        try {
            reply = await contractInstance.methods.setLatestData(testNotarization.serializednotarization, testNotarization.txid, testNotarization.voutnum,  testNotarization.abiencodedSigData).send({ from: accounts[0], gas: 6000000 });  
        } catch(e) {
            console.log(e)
            assert.isTrue(false);
        }
        // Get the contract balance after sending ETH exportHeights
        const notarization = await contractInstance.methods.bestForks(0).call();

         const NotarizationResult = {
           txid: notarization.substring(66, 130),
           n: parseInt(notarization.slice(202, 210), 16),
           hash: notarization.substring(2, 66),
        };
        assert.equal(`0x${NotarizationResult.txid}`, testNotarization.txid, "Txid in best forks does not equal notarization");
      });

      it("Test Serializer with bounceback sendTransfer", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        const prelaunchtx = `0x${reservetransfer.prelaunchfundETH.toBuffer().toString('hex')}`;
        const bounceback = `0x${reservetransfer.bounceback.toBuffer().toString('hex')}`;

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfer(bounceback).call();  
         //   console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }
        assert.equal(toBase58Check(Buffer.from(reply.secondreserveid.slice(2),'hex'), 102), reservetransfer.bounceback.second_reserve_id , "secondreserveid does not equal transaction");
      });

      it("Deserialize two Reserve transfers", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const twoTransfersSerialized = Buffer.concat([reservetransfer.twoReserveTransfers[0].toBuffer(), reservetransfer.twoReserveTransfers[1].toBuffer()]).toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${twoTransfersSerialized}`, 2).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }
        const txOne = new web3.utils.BN(reply.tempTransfers[0].currencyAndAmount).toString('hex').slice(7); 
        assert.equal(toBase58Check(Buffer.from(txOne,'hex'), 102), reservetransfer.twoReserveTransfers[0].reserve_values.value_map.keys().next().value , "transfer currency does not equal transaction");
      });

      it("Deserialize a Reserve transfer with a mapped ERC721", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc721transfer = reservetransfer.erc721transferETH.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc721transfer}${erc721transfer}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0x39Ec448b891c476e166b3C3242A90830DB556661" , "ERC721 does not equal transaction");
        assert.equal(reply.launchTxs[0].flags, "129" , "ERC721 does not equal transaction");
        assert.equal(reply.launchTxs[0].tokenID, 255 , "ERC721 TokenID does not equal the correct (first Currency Export)");
      });

      it("Deserialize a Reserve transfer with a verus owned ERC721", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc721transfer = reservetransfer.erc721transferVerus.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc721transfer}${erc721transfer}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency (chad7) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0x0000000000000000000000000000000000000000" , "ERC721 does not equal an empty address");
        assert.equal(reply.launchTxs[0].flags, "130" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a verus owned ERC20", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc20verustoken = reservetransfer.erc20verustoken.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc20verustoken}${erc20verustoken}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency (chad7) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0x0000000000000000000000000000000000000000" , "ERC20 does not equal verus ERC20 NFT address");
        assert.equal(reply.launchTxs[0].flags, "34" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a ETH owned ERC20", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc20ETHtoken = reservetransfer.erc20ETHtoken.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc20ETHtoken}${erc20ETHtoken}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency (chad7) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0xB897f2448054bc5b133268A53090e110D101FFf0" , "ERC20 does not equal DAI address (first Currency Export)");
        assert.equal(reply.launchTxs[1].ERCContract, "0xB897f2448054bc5b133268A53090e110D101FFf0" , "ERC20 does not equal DAI address (second Currency Export)");
        assert.equal(reply.launchTxs[0].flags, "33" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a ERC1155 Verus mapped nft", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc1155VerusNFT = reservetransfer.erc1155VerusNFT.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc1155VerusNFT}${erc1155VerusNFT}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "iAwycBuMcPJii45bKNTEfSnD9W9iXMiKGg" , "transfer currency (id2) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct address (first Currency Export)");
        assert.equal(reply.launchTxs[1].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].tokenID, 255 , "ERC1155 TokenID does not equal the correct (first Currency Export)");
        assert.equal(reply.launchTxs[1].tokenID, 255 , "ERC1155 TokenID does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].flags, "17" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a ERC1155 to token mapping", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc1155Token = reservetransfer.erc1155Token.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc1155Token}${erc1155Token}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "iAwycBuMcPJii45bKNTEfSnD9W9iXMiKGg" , "transfer currency (id2) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct (first Currency Export)");
        assert.equal(reply.launchTxs[1].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].tokenID, 255 , "ERC1155 TokenID does not equal the correct (first Currency Export)");
        assert.equal(reply.launchTxs[1].tokenID, 255 , "ERC1155 TokenID does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].flags, "65" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Check Verus ERC721 has launched", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        let tokensList = await DelegatorInst.getTokenList.call(0,0);

        const NFTContract = new web3.eth.Contract(ERC721.abi, tokensList[0].erc20ContractAddress);
       
        let reply;  
        try {
           reply = await NFTContract.methods.name().call(); ;

        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(reply, "VerusNFT" , "Verus ERC721 name does not equal transaction");
      });

});