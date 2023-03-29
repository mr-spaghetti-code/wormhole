// SPDX-License-Identifier: Apache 2

/// This module implements serialization and deserialization for token transfer
/// with an arbitrary payload. This message is a specific Wormhole message
/// payload for Token Bridge.
///
/// In order to redeem these types of transfers, one must have an `EmitterCap`
/// and the specified `redeemer` must agree with this capability.
///
/// See `transfer_tokens_with_payload` and `complete_transfer_with_payload`
/// modules for more details.
module token_bridge::transfer_with_payload {
    use std::vector::{Self};
    use wormhole::bytes::{Self};
    use wormhole::cursor::{Self};
    use wormhole::emitter::{Self, EmitterCap};
    use wormhole::external_address::{Self, ExternalAddress};

    use token_bridge::normalized_amount::{Self, NormalizedAmount};

    /// Message payload is not `TransferWithPayload`.
    const E_INVALID_PAYLOAD: u64 = 0;

    /// Message identifier.
    const PAYLOAD_ID: u8 = 3;

    /// Container that warehouses transfer information, including arbitrary
    /// payload.
    ///
    /// NOTE: This struct has `drop` because we do not want to require an
    /// integrator receiving transfer information to have to manually destroy.
    struct TransferWithPayload has drop {
        // Transfer amount.
        amount: NormalizedAmount,
        // Address of the token. Left-zero-padded if shorter than 32 bytes.
        token_address: ExternalAddress,
        // Chain ID of the token.
        token_chain: u16,
        // A.K.A. 32-byte representation of `EmitterCap`.
        redeemer: ExternalAddress,
        // Chain ID of the redeemer.
        redeemer_chain: u16,
        // Address of the message sender.
        sender: ExternalAddress,
        // An arbitrary payload.
        payload: vector<u8>,
    }

    /// Identifier for `TransferWithPayload`.
    public fun payload_id(): u8 {
        PAYLOAD_ID
    }

    /// Create new `TransferWithPayload` using `EmitterCap` as the sender.
    public fun new_from_emitter(
        emitter_cap: &EmitterCap,
        amount: NormalizedAmount,
        token_address: ExternalAddress,
        token_chain: u16,
        redeemer: ExternalAddress,
        redeemer_chain: u16,
        payload: vector<u8>
    ): TransferWithPayload {
        new(
            amount,
            token_address,
            token_chain,
            redeemer,
            redeemer_chain,
            emitter::addr(emitter_cap),
            payload
        )
    }

    /// Decompose `TransferWithPayload` into its members.
    public fun unpack(
        transfer: TransferWithPayload
    ): (
        NormalizedAmount,
        ExternalAddress,
        u16,
        ExternalAddress,
        u16,
        ExternalAddress,
        vector<u8>
    ) {
        let TransferWithPayload {
            amount,
            token_address,
            token_chain,
            redeemer,
            redeemer_chain,
            sender,
            payload
        } = transfer;

        (
            amount,
            token_address,
            token_chain,
            redeemer,
            redeemer_chain,
            sender,
            payload
        )
    }

    /// Destroy `TransferWithPayload` and take only its payload.
    public fun take_payload(transfer: TransferWithPayload): vector<u8> {
        let (
            _,
            _,
            _,
            _,
            _,
            _,
            payload
        ) = unpack(transfer);
        payload
    }

    /// Retrieve normalized amount of token transfer.
    public fun amount(self: &TransferWithPayload): NormalizedAmount {
        self.amount
    }

    // Retrieve token's canonical address.
    public fun token_address(self: &TransferWithPayload): ExternalAddress {
        self.token_address
    }

    /// Retrieve token's canonical chain ID.
    public fun token_chain(self: &TransferWithPayload): u16 {
        self.token_chain
    }

    /// Retrieve expected redeemer.
    public fun redeemer(self: &TransferWithPayload): ExternalAddress {
        self.redeemer
    }

    /// Retrieve target chain for redeemer.
    public fun redeemer_chain(self: &TransferWithPayload): u16 {
        self.redeemer_chain
    }

    /// Retrieve transfer sender.
    public fun sender(self: &TransferWithPayload): ExternalAddress {
        self.sender
    }

    /// Retrieve arbitrary payload.
    public fun payload(self: &TransferWithPayload): vector<u8> {
        self.payload
    }

    /// Decode Wormhole message payload as `TransferWithPayload`.
    public fun deserialize(transfer: vector<u8>): TransferWithPayload {
        let cur = cursor::new(transfer);
        assert!(bytes::take_u8(&mut cur) == PAYLOAD_ID, E_INVALID_PAYLOAD);

        let amount = normalized_amount::take_bytes(&mut cur);
        let token_address = external_address::take_bytes(&mut cur);
        let token_chain = bytes::take_u16_be(&mut cur);
        let redeemer = external_address::take_bytes(&mut cur);
        let redeemer_chain = bytes::take_u16_be(&mut cur);
        let sender = external_address::take_bytes(&mut cur);

        new(
            amount,
            token_address,
            token_chain,
            redeemer,
            redeemer_chain,
            sender,
            cursor::take_rest(cur)
        )
    }

    /// Encode `TransferWithPayload` for Wormhole message payload.
    public fun serialize(transfer: TransferWithPayload): vector<u8> {
        let (
            amount,
            token_address,
            token_chain,
            redeemer,
            redeemer_chain,
            sender,
            payload
        ) = unpack(transfer);

        let buf = vector::empty<u8>();
        bytes::push_u8(&mut buf, PAYLOAD_ID);
        bytes::push_u256_be(&mut buf, normalized_amount::to_u256(amount));
        vector::append(&mut buf, external_address::to_bytes(token_address));
        bytes::push_u16_be(&mut buf, token_chain);
        vector::append(&mut buf, external_address::to_bytes(redeemer));
        bytes::push_u16_be(&mut buf, redeemer_chain);
        vector::append(&mut buf, external_address::to_bytes(sender));
        vector::append(&mut buf, payload);

        buf
    }

    fun new(
        amount: NormalizedAmount,
        token_address: ExternalAddress,
        token_chain: u16,
        redeemer: ExternalAddress,
        redeemer_chain: u16,
        sender: ExternalAddress,
        payload: vector<u8>
    ): TransferWithPayload {
        TransferWithPayload {
            amount,
            token_address,
            token_chain,
            redeemer,
            redeemer_chain,
            sender,
            payload
        }
    }

    #[test_only]
    public fun destroy(transfer: TransferWithPayload) {
        unpack(transfer);
    }
}

#[test_only]
module token_bridge::transfer_with_payload_tests {
    use std::vector::{Self};
    use wormhole::emitter::{Self};
    use wormhole::external_address::{Self};

    use token_bridge::dummy_message::{Self};
    use token_bridge::normalized_amount::{Self};
    use token_bridge::transfer_with_payload::{Self};

    #[test]
    fun test_serialize() {
        let emitter_cap =
            emitter::dummy_cap(external_address::from_any_bytes(x"deadbeef"));
        let amount = normalized_amount::from_raw(234567890, 8);
        let token_address = external_address::from_any_bytes(x"beef");
        let token_chain = 1;
        let redeemer = external_address::from_any_bytes(x"cafe");
        let redeemer_chain = 7;
        let payload = b"All your base are belong to us.";

        let new_transfer =
            transfer_with_payload::new_from_emitter(
                &emitter_cap,
                amount,
                token_address,
                token_chain,
                redeemer,
                redeemer_chain,
                payload
            );

        // Verify getters.
        assert!(
            transfer_with_payload::amount(&new_transfer) == amount,
            0
        );
        assert!(
            transfer_with_payload::token_address(&new_transfer) == token_address,
            0
        );
        assert!(
            transfer_with_payload::token_chain(&new_transfer) == token_chain,
            0
        );
        assert!(
            transfer_with_payload::redeemer(&new_transfer) == redeemer,
            0
        );
        assert!(
            transfer_with_payload::redeemer_chain(&new_transfer) == redeemer_chain,
            0
        );
        assert!(
            transfer_with_payload::sender(&new_transfer) == emitter::addr(&emitter_cap),
            0
        );
        assert!(
            transfer_with_payload::payload(&new_transfer) == payload,
            0
        );

        let serialized = transfer_with_payload::serialize(new_transfer);
        let expected_serialized =
            dummy_message::encoded_transfer_with_payload();
        assert!(serialized == expected_serialized, 0);

        // Clean up.
        emitter::destroy_cap(emitter_cap);
    }

    #[test]
    public fun test_deserialize() {
        let expected_amount = normalized_amount::from_raw(234567890, 8);
        let expected_token_address = external_address::from_any_bytes(x"beef");
        let expected_token_chain = 1;
        let expected_recipient = external_address::from_any_bytes(x"cafe");
        let expected_recipient_chain = 7;
        let expected_sender = external_address::from_any_bytes(x"deadbeef");
        let expected_payload = b"All your base are belong to us.";

        let parsed =
            transfer_with_payload::deserialize(
                dummy_message::encoded_transfer_with_payload()
            );

        // Verify getters.
        assert!(
            transfer_with_payload::amount(&parsed) == expected_amount,
            0
        );
        assert!(
            transfer_with_payload::token_address(&parsed) == expected_token_address,
            0
        );
        assert!(
            transfer_with_payload::token_chain(&parsed) == expected_token_chain,
            0
        );
        assert!(
            transfer_with_payload::redeemer(&parsed) == expected_recipient,
            0
        );
        assert!(
            transfer_with_payload::redeemer_chain(&parsed) == expected_recipient_chain,
            0
        );
        assert!(
            transfer_with_payload::sender(&parsed) == expected_sender,
            0
        );
        assert!(
            transfer_with_payload::payload(&parsed) == expected_payload,
            0
        );

        let (
            amount,
            token_address,
            token_chain,
            redeemer,
            redeemer_chain,
            sender,
            payload
        ) = transfer_with_payload::unpack(parsed);
        assert!(amount == expected_amount, 0);
        assert!(token_address == expected_token_address, 0);
        assert!(token_chain == expected_token_chain, 0);
        assert!(redeemer == expected_recipient, 0);
        assert!(redeemer_chain == expected_recipient_chain, 0);
        assert!(sender == expected_sender, 0);
        assert!(payload == expected_payload, 0);
    }

    #[test]
    #[expected_failure(abort_code = transfer_with_payload::E_INVALID_PAYLOAD)]
    public fun test_cannot_deserialize_invalid_payload() {
        let invalid_payload = token_bridge::dummy_message::encoded_transfer();

        // Show that the first byte is not the expected payload ID.
        assert!(
            *vector::borrow(&invalid_payload, 0) != transfer_with_payload::payload_id(),
            0
        );

        // You shall not pass!
        let parsed = transfer_with_payload::deserialize(invalid_payload);

        // Clean up.
        transfer_with_payload::destroy(parsed);
    }
}
