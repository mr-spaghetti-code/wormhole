module wormhole::update_guardian_set {
    use std::vector::{Self};
    use sui::tx_context::{TxContext};

    use wormhole::bytes::{Self};
    use wormhole::cursor::{Self};
    use wormhole::governance_message::{Self, GovernanceMessage};
    use wormhole::guardian::{Self, Guardian};
    use wormhole::guardian_set::{Self};
    use wormhole::state::{Self, State};

    const E_NO_GUARDIANS: u64 = 0;
    const E_NON_INCREMENTAL_GUARDIAN_SETS: u64 = 1;

    /// Specific governance payload ID (action) for updating the guardian set.
    const ACTION_UPDATE_GUARDIAN_SET: u8 = 2;

    struct UpdateGuardianSet {
        new_index: u32,
        guardians: vector<Guardian>,
    }

    public fun update_guardian_set(
        wormhole_state: &mut State,
        vaa_buf: vector<u8>,
        ctx: &TxContext
    ): u32 {
        let msg =
            governance_message::parse_and_verify_vaa(
                wormhole_state,
                vaa_buf,
                ctx
            );

        // Do not allow this VAA to be replayed (although it may be impossible
        // to do so due to the guardian set of a previous VAA being illegitimate
        // since `governance_message` requires new governance VAAs being signed
        // by the most recent guardian set).
        state::consume_vaa_hash(
            wormhole_state,
            governance_message::vaa_hash(&msg)
        );

        // Proceed with the update.
        handle_update_guardian_set(wormhole_state, msg, ctx)
    }

    fun handle_update_guardian_set(
        wormhole_state: &mut State,
        msg: GovernanceMessage,
        ctx: &TxContext
    ): u32 {
        // Verify that this governance message is to update the guardian set.
        let governance_payload =
            governance_message::take_global_action(
                msg,
                state::governance_module(),
                ACTION_UPDATE_GUARDIAN_SET
            );

        // Deserialize the payload as the updated guardian set.
        let UpdateGuardianSet {
            new_index,
            guardians
        } = deserialize(governance_payload);

        // Every new guardian set index must be incremental from the last known
        // guardian set.
        assert!(
            new_index == state::guardian_set_index(wormhole_state) + 1,
            E_NON_INCREMENTAL_GUARDIAN_SETS
        );

        // Expire the existing guardian set.
        state::expire_guardian_set(wormhole_state, ctx);

        // And store the new one.
        state::store_guardian_set(
            wormhole_state,
            guardian_set::new(new_index, guardians)
        );

        new_index
    }

    fun deserialize(payload: vector<u8>): UpdateGuardianSet {
        let cur = cursor::new(payload);
        let new_index = bytes::take_u32_be(&mut cur);
        let num_guardians = bytes::take_u8(&mut cur);
        assert!(num_guardians > 0, E_NO_GUARDIANS);

        let guardians = vector::empty<Guardian>();
        let i = 0;
        while (i < num_guardians) {
            let key = bytes::take_bytes(&mut cur, 20);
            vector::push_back(&mut guardians, guardian::new(key));
            i = i + 1;
        };
        cursor::destroy_empty(cur);

        UpdateGuardianSet { new_index, guardians }
    }

    #[test_only]
    public fun action(): u8 {
        ACTION_UPDATE_GUARDIAN_SET
    }
}

#[test_only]
module wormhole::guardian_set_upgrade_test {
    use std::vector::{Self};
    use sui::test_scenario::{Self};

    use wormhole::bytes::{Self};
    use wormhole::cursor::{Self};
    use wormhole::governance_message::{Self};
    use wormhole::guardian::{Self};
    use wormhole::guardian_set::{Self};
    use wormhole::state::{Self, State};
    use wormhole::update_guardian_set::{Self};
    use wormhole::wormhole_scenario::{set_up_wormhole, person};

    const VAA_UPDATE_GUARDIAN_SET_1: vector<u8> =
        x"010000000001004f74e9596bd8246ef456918594ae16e81365b52c0cf4490b2a029fb101b058311f4a5592baeac014dc58215faad36453467a85a4c3e1c6cf5166e80f6e4dc50b0100bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000010100000000000000000000000000000000000000000000000000000000436f72650200000000000113befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe88d7d8b32a9105d228100e72dffe2fae0705d31c58076f561cc62a47087b567c86f986426dfcd000bd6e9833490f8fa87c733a183cd076a6cbd29074b853fcf0a5c78c1b56d15fce7a154e6ebe9ed7a2af3503dbd2e37518ab04d7ce78b630f98b15b78a785632dea5609064803b1c8ea8bb2c77a6004bd109a281a698c0f5ba31f158585b41f4f33659e54d3178443ab76a60e21690dbfb17f7f59f09ae3ea1647ec26ae49b14060660504f4da1c2059e1c5ab6810ac3d8e1258bd2f004a94ca0cd4c68fc1c061180610e96d645b12f47ae5cf4546b18538739e90f2edb0d8530e31a218e72b9480202acbaeb06178da78858e5e5c4705cdd4b668ffe3be5bae4867c9d5efe3a05efc62d60e1d19faeb56a80223cdd3472d791b7d32c05abb1cc00b6381fa0c4928f0c56fc14bc029b8809069093d712a3fd4dfab31963597e246ab29fc6ebedf2d392a51ab2dc5c59d0902a03132a84dfd920b35a3d0ba5f7a0635df298f9033e";
    const VAA_UPDATE_GUARDIAN_SET_2A: vector<u8> =
        x"010000000001005fb17d5e0e736e3014756bf7e7335722c4fe3ad18b5b1b566e8e61e562cc44555f30b298bc6a21ea4b192a6f1877a5e638ecf90a77b0b028f297a3a70d93614d0100bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000010100000000000000000000000000000000000000000000000000000000436f72650200000000000101befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe";
    const VAA_UPDATE_GUARDIAN_SET_2B: vector<u8> =
        x"01000000010100195f37abd29438c74db6e57bf527646b36fa96e36392221e869debe0e911f2f319abc0fd5c5a454da76fc0ffdd23a71a60bca40aa4289a841ad07f2964cde9290000bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000020100000000000000000000000000000000000000000000000000000000436f72650200000000000201befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe";
    const VAA_BOGUS_TARGET_CHAIN: vector<u8> =
        x"0100000000010004b514098f76a23591c7b65dc65320e40a0c402e0b429fb5d7608f7f97b9f5cb04fa5b25f80c546a2236f4109a542d87cd86a54db1ee94317d39863194dff8f00100bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000010100000000000000000000000000000000000000000000000000000000436f72650200150000000101befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe";
    const VAA_BOGUS_ACTION: vector<u8> =
        x"01000000000100bd1aa227e7b3b9d3776105cb383c6197c8761266c895c478d9d30f5932447b156f2307df6fc7ca955806a618ef757cc061b29ee33657d638a33343c907fad4a30100bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000010100000000000000000000000000000000000000000000000000000000436f72654500000000000101befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe";
    const VAA_UPDATE_GUARDIAN_SET_EMPTY: vector<u8> =
        x"0100000000010098f9e45f836661d2932def9c74c587168f4f75d0282201ee6f5a98557e6212ff19b0f8881c2750646250f60dd5d565530779ecbf9442aa5ffc2d6afd7303aaa40000bc614e000000000001000000000000000000000000000000000000000000000000000000000000000400000000000000010100000000000000000000000000000000000000000000000000000000436f72650200000000000100";

    #[test]
    public fun test_update_guardian_set() {
        // Testing this method.
        use wormhole::update_guardian_set::{update_guardian_set};

        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test to execute `update_guardian_set`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);
        let new_index = update_guardian_set(
            &mut worm_state,
            VAA_UPDATE_GUARDIAN_SET_1,
            test_scenario::ctx(scenario)
        );
        assert!(new_index == 1, 0);

        let new_guardian_set = state::guardian_set_at(&worm_state, new_index);

        // Verify new guardian set index.
        assert!(state::guardian_set_index(&worm_state) == new_index, 0);
        assert!(
            guardian_set::index(new_guardian_set) == state::guardian_set_index(&worm_state),
            0
        );

        // Check that the guardians agree with what we expect.
        let guardians = guardian_set::guardians(new_guardian_set);
        let expected = vector[
            guardian::new(x"befa429d57cd18b7f8a4d91a2da9ab4af05d0fbe"),
            guardian::new(x"88d7d8b32a9105d228100e72dffe2fae0705d31c"),
            guardian::new(x"58076f561cc62a47087b567c86f986426dfcd000"),
            guardian::new(x"bd6e9833490f8fa87c733a183cd076a6cbd29074"),
            guardian::new(x"b853fcf0a5c78c1b56d15fce7a154e6ebe9ed7a2"),
            guardian::new(x"af3503dbd2e37518ab04d7ce78b630f98b15b78a"),
            guardian::new(x"785632dea5609064803b1c8ea8bb2c77a6004bd1"),
            guardian::new(x"09a281a698c0f5ba31f158585b41f4f33659e54d"),
            guardian::new(x"3178443ab76a60e21690dbfb17f7f59f09ae3ea1"),
            guardian::new(x"647ec26ae49b14060660504f4da1c2059e1c5ab6"),
            guardian::new(x"810ac3d8e1258bd2f004a94ca0cd4c68fc1c0611"),
            guardian::new(x"80610e96d645b12f47ae5cf4546b18538739e90f"),
            guardian::new(x"2edb0d8530e31a218e72b9480202acbaeb06178d"),
            guardian::new(x"a78858e5e5c4705cdd4b668ffe3be5bae4867c9d"),
            guardian::new(x"5efe3a05efc62d60e1d19faeb56a80223cdd3472"),
            guardian::new(x"d791b7d32c05abb1cc00b6381fa0c4928f0c56fc"),
            guardian::new(x"14bc029b8809069093d712a3fd4dfab31963597e"),
            guardian::new(x"246ab29fc6ebedf2d392a51ab2dc5c59d0902a03"),
            guardian::new(x"132a84dfd920b35a3d0ba5f7a0635df298f9033e"),
        ];
        assert!(vector::length(&expected) == vector::length(guardians), 0);

        let cur = cursor::new(expected);
        let i = 0;
        while (!cursor::is_empty(&cur)) {
            let left = guardian::as_bytes(vector::borrow(guardians, i));
            let right = guardian::to_bytes(cursor::poke(&mut cur));
            assert!(left == right, 0);
            i = i + 1;
        };
        cursor::destroy_empty(cur);

        // Make sure old guardian set is still active.
        let old_guardian_set =
            state::guardian_set_at(&worm_state, new_index - 1);
        assert!(
            guardian_set::is_active(
                old_guardian_set,
                test_scenario::ctx(scenario)
            ),
            0
        );

        // Fast forward time beyond expiration by 3 epochs
        test_scenario::next_epoch(scenario, caller);
        test_scenario::next_epoch(scenario, caller);
        test_scenario::next_epoch(scenario, caller);

        // Now the old guardian set should be expired (because in the test setup
        // time to live is set to 2 epochs).
        assert!(
            !guardian_set::is_active(
                old_guardian_set,
                test_scenario::ctx(scenario)
            ),
            0
        );

        // Clean up.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(
        abort_code = governance_message::E_OLD_GUARDIAN_SET_GOVERNANCE
    )]
    public fun test_cannot_update_guardian_set_again_with_same_vaa() {
        // Testing this method.
        use wormhole::update_guardian_set::{update_guardian_set};

        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test to execute `update_guardian_set`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);
        update_guardian_set(
            &mut worm_state,
            VAA_UPDATE_GUARDIAN_SET_2A,
            test_scenario::ctx(scenario)
        );

        // Update guardian set again with new VAA.
        update_guardian_set(
            &mut worm_state,
            VAA_UPDATE_GUARDIAN_SET_2B,
            test_scenario::ctx(scenario)
        );
        assert!(state::guardian_set_index(&worm_state) == 2, 0);

        // Cannot replay first VAA due to stale guardian set index.
        update_guardian_set(
            &mut worm_state,
            VAA_UPDATE_GUARDIAN_SET_2A,
            test_scenario::ctx(scenario)
        );

        // Clean up even though we should have failed by this point.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(
        abort_code = governance_message::E_GOVERNANCE_TARGET_CHAIN_NONZERO
    )]
    public fun test_cannot_update_guardian_set_invalid_target_chain() {
        // Testing this method.
        use wormhole::update_guardian_set::{update_guardian_set};

        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test to execute `update_guardian_set`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        // Updating the guardidan set must be applied globally (not for just
        // one chain).
        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_BOGUS_TARGET_CHAIN,
                test_scenario::ctx(scenario)
            );
        assert!(!governance_message::is_global_action(&msg), 0);
        governance_message::destroy(msg);

        // You shall not pass!
        update_guardian_set(
            &mut worm_state,
            VAA_BOGUS_TARGET_CHAIN,
            test_scenario::ctx(scenario)
        );

        // Clean up even though we should have failed by this point.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(
        abort_code = governance_message::E_INVALID_GOVERNANCE_ACTION
    )]
    public fun test_cannot_update_guardian_set_invalid_action() {
        // Testing this method.
        use wormhole::update_guardian_set::{update_guardian_set};

        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test to execute `update_guardian_set`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        // Updating the guardidan set must be applied globally (not for just
        // one chain).
        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_BOGUS_ACTION,
                test_scenario::ctx(scenario)
            );
        assert!(
            governance_message::action(&msg) != update_guardian_set::action(),
            0
        );
        governance_message::destroy(msg);

        // You shall not pass!
        update_guardian_set(
            &mut worm_state,
            VAA_BOGUS_ACTION,
            test_scenario::ctx(scenario)
        );

        // Clean up even though we should have failed by this point.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }

    #[test]
    #[expected_failure(abort_code = update_guardian_set::E_NO_GUARDIANS)]
    public fun test_cannot_update_guardian_set_with_no_guardians() {
        // Testing this method.
        use wormhole::update_guardian_set::{update_guardian_set};

        // Set up.
        let caller = person();
        let my_scenario = test_scenario::begin(caller);
        let scenario = &mut my_scenario;

        let wormhole_fee = 0;
        set_up_wormhole(scenario, wormhole_fee);

        // Prepare test to execute `update_guardian_set`.
        test_scenario::next_tx(scenario, caller);

        let worm_state = test_scenario::take_shared<State>(scenario);

        // Show that the encoded number of guardians is zero.
        let msg =
            governance_message::parse_and_verify_vaa(
                &mut worm_state,
                VAA_UPDATE_GUARDIAN_SET_EMPTY,
                test_scenario::ctx(scenario)
            );
        let payload = governance_message::take_payload(msg);
        let cur = cursor::new(payload);

        let new_guardian_set_index = bytes::take_u32_be(&mut cur);
        assert!(new_guardian_set_index == 1, 0);

        let num_guardians = bytes::take_u8(&mut cur);
        assert!(num_guardians == 0, 0);

        cursor::destroy_empty(cur);

        // You shall not pass!
        update_guardian_set(
            &mut worm_state,
            VAA_UPDATE_GUARDIAN_SET_EMPTY,
            test_scenario::ctx(scenario)
        );

        // Clean up even though we should have failed by this point.
        test_scenario::return_shared(worm_state);

        // Done.
        test_scenario::end(my_scenario);
    }
}
