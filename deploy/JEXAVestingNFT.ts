import { keccak256 } from '@layerzerolabs/lz-v2-utilities'
import assert from 'assert'
import { toUtf8Bytes } from 'ethers/lib/utils'

import { type DeployFunction } from 'hardhat-deploy/types'

const contractName = 'JEXAVestingNFT'
const JEXAToken = '0x8B0aE40C03994Abc55654b51b3a5f2D0d0c7cAd9';

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre

    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log("Deploying JEXAVestingNFT")
    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)

    console.log("Using JEXA Token address:", JEXAToken);

    const salt = keccak256(toUtf8Bytes('Jexica AI (Staging)'));

    const { address } = await deploy(contractName, {
        from: deployer,
        args: [
            JEXAToken
        ],
        deterministicDeployment: salt,
        log: true,
        skipIfAlreadyDeployed: false,
    })

    console.log(`Deployed contract: ${contractName}, network: ${hre.network.name}, address: ${address}`)
}

deploy.tags = [contractName]

export default deploy
