#!/bin/bash -f

. env.sh

echo "Creating wrapped asset..."
echo "$COIN_PACKAGE::coin_witness::COIN_WITNESS"


sui client call --function create_wrapped_coin_test_1 --module wrapped --package $TOKEN_PACKAGE --gas-budget 20000 \
--args \"$WORM_STATE\" \"$TOKEN_STATE\" \
--type-args "$COIN_PACKAGE::coin_witness::COIN_WITNESS"

sui client call --function create_wrapped_coin_test_2 --module wrapped --package $TOKEN_PACKAGE --gas-budget 20000 \
--args \"$WORM_STATE\" \"$TOKEN_STATE\" \"$TREASURY_CAP\" "0x0100000000010080366065746148420220f25a6275097370e8db40984529a6676b7a5fc9feb11755ec49ca626b858ddfde88d15601f85ab7683c5f161413b0412143241c700aff010000000100000001000200000000000000000000000000000000000000000000000000000000deadbeef000000000150eb23000200000000000000000000000000000000000000000000000000000000beefface00020c424545460000000000000000000000000000000000000000000000000000000042656566206661636520546f6b656e0000000000000000000000000000000000" \
--type-args "$COIN_PACKAGE::coin_witness::COIN_WITNESS"

sui client call --function create_wrapped_coin_test_3 --module wrapped --package $TOKEN_PACKAGE --gas-budget 20000 \
--args \"$WORM_STATE\" \"$TOKEN_STATE\" \"$TREASURY_CAP\" "0x0100000000010080366065746148420220f25a6275097370e8db40984529a6676b7a5fc9feb11755ec49ca626b858ddfde88d15601f85ab7683c5f161413b0412143241c700aff010000000100000001000200000000000000000000000000000000000000000000000000000000deadbeef000000000150eb23000200000000000000000000000000000000000000000000000000000000beefface00020c424545460000000000000000000000000000000000000000000000000000000042656566206661636520546f6b656e0000000000000000000000000000000000" \
--type-args "$COIN_PACKAGE::coin_witness::COIN_WITNESS"

sui client call --function create_wrapped_coin_test_5 --module wrapped --package $TOKEN_PACKAGE --gas-budget 20000 \
--args \"$WORM_STATE\" \"$TOKEN_STATE\" \"$TREASURY_CAP\" "0x0100000000010080366065746148420220f25a6275097370e8db40984529a6676b7a5fc9feb11755ec49ca626b858ddfde88d15601f85ab7683c5f161413b0412143241c700aff010000000100000001000200000000000000000000000000000000000000000000000000000000deadbeef000000000150eb23000200000000000000000000000000000000000000000000000000000000beefface00020c424545460000000000000000000000000000000000000000000000000000000042656566206661636520546f6b656e0000000000000000000000000000000000" \
--type-args "$COIN_PACKAGE::coin_witness::COIN_WITNESS"