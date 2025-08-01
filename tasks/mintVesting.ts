import { task } from 'hardhat/config'

/**
 * hardhat mintVesting --start 1690000000 --duration 7776000 --amount 1000 --recipient 0x...
 */
task('mintVesting', 'Mint a new vesting NFT')
    .addParam('start', 'Unix start timestamp')
    .addParam('duration', 'Duration in seconds')
    .addParam('amount', 'Amount of JEXA (18 decimals)')
    .addOptionalParam('recipient', 'Recipient address (defaults to signer)')
    .setAction(async (args, hre) => {
        const { ethers } = hre
        const signer = (await ethers.getSigners())[0]
        const recipient = args.recipient ?? signer.address

        const vest = await ethers.getContract('JEXAVestingNFT', signer)
        const token = await ethers.getContract('JEXAToken', signer)

        const amt = ethers.utils.parseUnits(args.amount, 18)

        // approval if needed
        const allowance = await token.allowance(signer.address, vest.address)
        if (allowance.lt(amt)) {
            const tx = await token.approve(vest.address, amt)
            await tx.wait()
            console.log('Approved', amt.toString())
        }

        const tx = await vest.mintVesting(args.start, args.duration, amt, { gasLimit: 1_000_000 })
        const receipt = await tx.wait()
        console.log('mint tx hash', receipt.transactionHash)
    })
