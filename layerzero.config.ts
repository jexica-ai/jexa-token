import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

const mainnetContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET,
    contractName: 'JEXAToken',
}

const arbitrumContract: OmniPointHardhat = {
    eid: EndpointId.ARBITRUM_V2_MAINNET,
    contractName: 'JEXAToken',
}

const baseContract: OmniPointHardhat = {
    eid: EndpointId.BASE_V2_MAINNET,
    contractName: 'JEXAToken',
}

const bscContract: OmniPointHardhat = {
    eid: EndpointId.BSC_V2_MAINNET,
    contractName: 'JEXAToken',
}

// To connect all the above chains to each other, we need the following pathways:
// Ethereum <-> Arbitrum
// Ethereum <-> Base
// Ethereum <-> BSC
// Arbitrum <-> Base
// Arbitrum <-> BSC
// Base <-> BSC

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1,
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 65000,
        value: 0,
    },
]

// With the config generator, pathways declared are automatically bidirectional
// i.e. if you declare A,B there's no need to declare B,A
const pathways: TwoWayConfig[] = [
    [
        mainnetContract,
        arbitrumContract,
        [['LayerZero Labs', 'Google'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
        [15, 20], // [A to B confirmations, B to A confirmations]
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions
    ],
    [
        mainnetContract,
        baseContract,
        [['LayerZero Labs', 'Google'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
        [15, 10], // [A to B confirmations, B to A confirmations]
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions
    ],
    [
        mainnetContract,
        bscContract,
        [['LayerZero Labs', 'Google'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
        [15, 20], // [A to B confirmations, B to A confirmations]
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions
    ],
    [
        arbitrumContract,
        baseContract,
        [['LayerZero Labs', 'Google'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
        [20, 10], // [A to B confirmations, B to A confirmations]
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions
    ],
    [
        arbitrumContract,
        bscContract,
        [['LayerZero Labs', 'Google'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
        [20, 20], // [A to B confirmations, B to A confirmations]
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions
    ],
    [
        baseContract,
        bscContract,
        [['LayerZero Labs', 'Google'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
        [10, 20], // [A to B confirmations, B to A confirmations]
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain C enforcedOptions, Chain A enforcedOptions
    ]
]

export default async function () {
    // Generate the connections config based on the pathways
    const connections = await generateConnectionsConfig(pathways)
    return {
        contracts: [
            { contract: mainnetContract },
            { contract: arbitrumContract },
            { contract: baseContract },
            { contract: bscContract }
        ],
        connections,
    }
}
