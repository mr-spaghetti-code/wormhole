module Wormhole::Structs{

	struct Provider {
        chainId: u64, // u16
		governanceChainId: u64, // U16
        governanceContract: vector<u8>, //bytes32
	}

    struct Signature {
        r: vector<u8>, 
        s: vector<u8>, 
        v: u8, 
        guardianIndex: u8, 
	}

    struct VM {
        version: u8, 
        timestamp: u64, //u32
        nonce: u64, //u32 
        emitterChainId: u64, //u32 
        emitterAddress: vector<u8>,
        sequence: u64, 
        consistencyLevel: u8, 
        payload: vector<u8>, 

        guardianSetIndex: u64, //u32 
        signatures: vector<Signature>, 
        hash: vector<u8>,
	}

} 