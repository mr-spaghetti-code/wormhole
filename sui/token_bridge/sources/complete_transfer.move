module token_bridge::complete_transfer {
    use sui::tx_context::{TxContext};
    use sui::transfer::{Self as transfer_object};
    use sui::coin;

    use wormhole::state::{State as WormholeState};
    use wormhole::external_address::{Self};

    use token_bridge::bridge_state::{Self, BridgeState, VerifiedCoinType};
    use token_bridge::vaa::{Self};
    use token_bridge::transfer::{Self, Transfer};
    use token_bridge::normalized_amount::{denormalize};

    const E_INVALID_TARGET: u64 = 0;

    public entry fun submit_vaa<CoinType>(
        wormhole_state: &mut WormholeState,
        bridge_state: &mut BridgeState,
        vaa: vector<u8>,
        fee_recipient: address,
        ctx: &mut TxContext
    ) {

        let vaa = vaa::parse_verify_and_replay_protect(
            wormhole_state,
            bridge_state,
            vaa,
            ctx
        );

        let transfer = transfer::parse(wormhole::myvaa::destroy(vaa));

        let token_chain = transfer::get_token_chain(&transfer);
        let token_address = transfer::get_token_address(&transfer);
        let verified_coin_witness = bridge_state::verify_coin_type<CoinType>(
            bridge_state,
            token_chain,
            token_address
        );

        complete_transfer<CoinType>(
            verified_coin_witness,
            &transfer,
            wormhole_state,
            bridge_state,
            fee_recipient,
            ctx
        );
    }

    // complete transfer with arbitrary Transfer request and without the VAA
    #[test_only]
    public fun test_complete_transfer<CoinType>(
        transfer: &Transfer,
        wormhole_state: &mut WormholeState,
        bridge_state: &mut BridgeState,
        fee_recipient: address,
        ctx: &mut TxContext
    ) {
        let token_chain = transfer::get_token_chain(transfer);
        let token_address = transfer::get_token_address(transfer);
        let verified_coin_witness = bridge_state::verify_coin_type<CoinType>(
            bridge_state,
            token_chain,
            token_address
        );
        complete_transfer<CoinType>(
            verified_coin_witness,
            transfer,
            wormhole_state,
            bridge_state,
            fee_recipient,
            ctx
        );
    }

    fun complete_transfer<CoinType>(
        verified_coin_witness: VerifiedCoinType<CoinType>,
        transfer: &Transfer,
        wormhole_state: &mut WormholeState,
        bridge_state: &mut BridgeState,
        fee_recipient: address,
        ctx: &mut TxContext
    ) {
        let to_chain = transfer::get_to_chain(transfer);
        let this_chain = wormhole::state::get_chain_id(wormhole_state);
        assert!(to_chain == this_chain, E_INVALID_TARGET);

        let recipient = external_address::to_address(&transfer::get_to(transfer));

        // TODO - figure out actual number of decimal places to denormalize by
        //        Where to store or how to find out #decimals for coin?
        let decimals = 0;
        let amount = denormalize(transfer::get_amount(transfer), decimals);
        let fee_amount = denormalize(transfer::get_fee(transfer), decimals);

        let recipient_coins;
        if (bridge_state::is_wrapped_asset<CoinType>(bridge_state)) {
            recipient_coins = bridge_state::mint<CoinType>(
                verified_coin_witness,
                bridge_state,
                amount,
                ctx
            );
        } else {
            recipient_coins = bridge_state::withdraw<CoinType>(
                verified_coin_witness,
                bridge_state,
                amount,
                ctx
            );
        };
        // take out fee from the recipient's coins. `extract` will revert
        // if fee > amount
        let fee_coins = coin::split(&mut recipient_coins, fee_amount, ctx);
        transfer_object::transfer(recipient_coins, recipient);
        transfer_object::transfer(fee_coins, fee_recipient);
    }
}

#[test_only]
module token_bridge::test_complete_transfer {
    use std::bcs::{Self};

    use sui::test_scenario::{Self, Scenario, next_tx, return_shared, take_shared, ctx, take_from_address, return_to_address};
    use sui::coin::{Self, Coin};

    use wormhole::myu16::{Self as u16};
    use wormhole::external_address::{Self};

    use token_bridge::normalized_amount::{Self};
    use token_bridge::transfer::{Self, Transfer};
    use token_bridge::bridge_state::{Self, BridgeState};
    use token_bridge::coin_witness::{COIN_WITNESS};
    use token_bridge::coin_witness_test::{test_register_wrapped_};
    use token_bridge::complete_transfer::{Self};
    use token_bridge::native_coin_witness::{Self, NATIVE_COIN_WITNESS};
    use token_bridge::test_bridge_state::{set_up_wormhole_core_and_token_bridges};

    use wormhole::state::{Self as wormhole_state, State};

    fun scenario(): Scenario { test_scenario::begin(@0x123233) }
    fun people(): (address, address, address) { (@0x124323, @0xE05, @0xFACE) }

    #[test]
    fun complete_native_transfer_test(){
        let (admin, fee_recipient_person, _) = people();
        let test = scenario();
        test = set_up_wormhole_core_and_token_bridges(admin, test);
        // register native asset type with the token bridge
        next_tx(&mut test, admin);{
            let bridge_state = take_shared<BridgeState>(&test);
            let worm_state = take_shared<State>(&test);
            bridge_state::register_native_asset<NATIVE_COIN_WITNESS>(
                &mut worm_state,
                &mut bridge_state,
                ctx(&mut test)
            );
            native_coin_witness::test_init(ctx(&mut test));
            return_shared<BridgeState>(bridge_state);
            return_shared<State>(worm_state);
        };
        // create a treasury cap for the native asset type, mint some tokens,
        // and deposit the native tokens into the token bridge
        next_tx(&mut test, admin); {
            let bridge_state = take_shared<BridgeState>(&test);
            let worm_state = take_shared<State>(&test);
            let t_cap = take_shared<coin::TreasuryCap<NATIVE_COIN_WITNESS>>(&test);
            let coins = coin::mint<NATIVE_COIN_WITNESS>(&mut t_cap, 10000000000, ctx(&mut test));
            bridge_state::deposit<NATIVE_COIN_WITNESS>(&mut bridge_state, coins);
            return_shared<coin::TreasuryCap<NATIVE_COIN_WITNESS>>(t_cap);
            return_shared<BridgeState>(bridge_state);
            return_shared<State>(worm_state);
        };
        // complete transfer, sending native tokens to a recipient address
        next_tx(&mut test, admin); {
            let bridge_state = take_shared<BridgeState>(&test);
            let worm_state = take_shared<State>(&test);

            let to = admin;
            let amount = 1000000000;
            let fee_amount = 100000000;
            let decimals = 8;
            let token_address = external_address::from_bytes(x"01");
            let token_chain = wormhole_state::get_chain_id(&worm_state);
            let to_chain = wormhole_state::get_chain_id(&worm_state);

            let transfer: Transfer = transfer::create(
                normalized_amount::normalize(amount, decimals),
                token_address,
                token_chain,
                external_address::from_bytes(bcs::to_bytes(&to)),
                to_chain,
                normalized_amount::normalize(fee_amount, decimals),
            );

            complete_transfer::test_complete_transfer<NATIVE_COIN_WITNESS>(
                &transfer,
                &mut worm_state,
                &mut bridge_state,
                fee_recipient_person,
                ctx(&mut test)
            );
            return_shared<BridgeState>(bridge_state);
            return_shared<State>(worm_state);
        };

        // check balances after
        next_tx(&mut test, admin);{
            let coins = take_from_address<Coin<NATIVE_COIN_WITNESS>>(&test, admin);
            assert!(coin::value<NATIVE_COIN_WITNESS>(&coins) == 900000000, 0);
            return_to_address<Coin<NATIVE_COIN_WITNESS>>(admin, coins);

            let fee_coins = take_from_address<Coin<NATIVE_COIN_WITNESS>>(&test, fee_recipient_person);
            assert!(coin::value<NATIVE_COIN_WITNESS>(&fee_coins) == 100000000, 0);
            return_to_address<Coin<NATIVE_COIN_WITNESS>>(fee_recipient_person, fee_coins);
        };
        test_scenario::end(test);
    }

    // the following test is for the "beefface" token from ethereum (chain id = 2),
    // which has 8 decimals
    #[test]
    fun complete_wrapped_transfer_test(){
        let (admin, fee_recipient_person, _) = people();
        let scenario = scenario();
        // First register foreign chain, create wrapped asset, register wrapped asset.
        let test = test_register_wrapped_(admin, scenario);
        // Complete transfer of wrapped asset from foreign chain to this chain.
        next_tx(&mut test, admin); {
            let bridge_state = take_shared<BridgeState>(&test);
            let worm_state = take_shared<State>(&test);

            let to = admin;
            let amount = 1000000000;
            let fee_amount = 100000000;
            let decimals = 8;
            let token_address = external_address::from_bytes(x"beefface");
            let token_chain = u16::from_u64(2);
            let to_chain = wormhole_state::get_chain_id(&worm_state);

            let transfer: Transfer = transfer::create(
                normalized_amount::normalize(amount, decimals),
                token_address,
                token_chain,
                external_address::from_bytes(bcs::to_bytes(&to)),
                to_chain,
                normalized_amount::normalize(fee_amount, decimals),
            );

            complete_transfer::test_complete_transfer<COIN_WITNESS>(
                &transfer,
                &mut worm_state,
                &mut bridge_state,
                fee_recipient_person,
                ctx(&mut test)
            );
            return_shared<BridgeState>(bridge_state);
            return_shared<State>(worm_state);
        };

        // check balances after
        next_tx(&mut test, admin);{
            let coins = take_from_address<Coin<COIN_WITNESS>>(&test, admin);
            assert!(coin::value<COIN_WITNESS>(&coins) == 900000000, 0);
            return_to_address<Coin<COIN_WITNESS>>(admin, coins);

            let fee_coins = take_from_address<Coin<COIN_WITNESS>>(&test, fee_recipient_person);
            assert!(coin::value<COIN_WITNESS>(&fee_coins) == 100000000, 0);
            return_to_address<Coin<COIN_WITNESS>>(fee_recipient_person, fee_coins);
        };
        test_scenario::end(test);
    }
}
