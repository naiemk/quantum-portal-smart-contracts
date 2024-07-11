import { ethers } from "hardhat";
import { QuantumPortalUtils, deployAll } from "../poc/QuantumPortalUtils";
import { PingPong } from '../../../typechain-types/PingPong';
import { Wei } from "foundry-contracts/dist/test/common/Utils";

describe('Test ping-pong example', function() {
	it('Ping, pong until there is fee to pay', async function() {
        const ctx = await deployAll(); // Deploy QP
        console.log('Create the multi-chain ping-pong');

        const pingPongF = await ethers.getContractFactory('PingPong');

        const gasEstimate = 7000000 * 10**9; // Arbitrary number for simpler example
        const p1 = await pingPongF.deploy(ctx.chain2.chainId, gasEstimate) as PingPong;
        const p2 = await pingPongF.deploy(ctx.chain1.chainId, gasEstimate) as PingPong;

        // Initializing multi-chain connections
        p1.updateRemotePeers([ctx.chain2.chainId],[p2.address]);
        p1.initializeWithQp(ctx.chain1.poc.address);
        p2.updateRemotePeers([ctx.chain1.chainId],[p1.address]);
        p2.initializeWithQp(ctx.chain2.poc.address);

        // Send some token to contracts for gas
        await ctx.chain1.token.transfer(p1.address, Wei.from('10'));
        await ctx.chain2.token.transfer(p2.address, Wei.from('10'));

        const printCounters = async () => {
          console.log('CHAIN 1 COUNTER: ', (await p1.counter()).toString());
          console.log('CHAIN 2 COUNTER: ', (await p2.counter()).toString());
        }

        await printCounters();
        // Call ping remotely
        await p1.callPing();

        for(let i=0; i<10; i++) {
          // QP Mining....
          await QuantumPortalUtils.mineAndFinilizeOneToTwo(ctx, 0);
          await printCounters();

          // Now the other side...
          await QuantumPortalUtils.mineAndFinilizeTwoToOne(ctx, 0);
          await printCounters();
        }
    });
});