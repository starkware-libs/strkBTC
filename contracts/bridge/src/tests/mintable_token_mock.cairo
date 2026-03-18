use starknet::ContractAddress;

#[starknet::interface]
pub trait IMintableTokenMock<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn total_supply(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod mintable_token_mock {
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starkware_utils::interfaces::mintable_token::IMintableToken;
    use strkbtc_bridge::tests::mintable_token_mock::IMintableTokenMock;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        total_supply: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl MintableImpl of IMintableToken<ContractState> {
        fn permissioned_mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            let balance = self.balances.entry(account).read();
            self.balances.entry(account).write(balance + amount);
            self.total_supply.write(self.total_supply.read() + amount);
        }

        fn permissioned_burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            let balance = self.balances.entry(account).read();
            assert(balance >= amount, 'INSUFFICIENT_BALANCE');
            self.balances.entry(account).write(balance - amount);
            self.total_supply.write(self.total_supply.read() - amount);
        }

        fn is_permitted_minter(self: @ContractState, account: ContractAddress) -> bool {
            true
        }
    }

    #[abi(embed_v0)]
    impl MockViewImpl of IMintableTokenMock<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.entry(account).read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }
    }
}
