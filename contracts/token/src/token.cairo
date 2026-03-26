//! SPDX-License-Identifier: Apache-2.0.
//!
//! # ERC20 Mintable Token
//!
//! A mintable ERC20 token with:
//! - Permissioned minting/burning by a designated minter (e.g., bridge)
//! - Role-based access control (Governance Admin, Upgrade Governor)
//! - Replaceability (upgradeable with time delay)

#[starknet::contract]
pub mod token {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::IERC20Metadata;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::interfaces::mintable_token::IMintableToken;

    // Components
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);

    // External - ERC20
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;

    // External - Replaceability
    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    // External - Roles
    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    // Internal
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        // --- Token specific ---
        // Note: Named ERC20_decimals for storage compatibility with legacy contracts
        ERC20_decimals: u8,
        permitted_minter: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
    }

    pub mod Errors {
        pub const INVALID_MINTER: felt252 = 'INVALID_MINTER_ADDRESS';
        pub const ONLY_MINTER: felt252 = 'MINTER_ONLY';
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        decimals: u8,
        initial_supply: u256,
        recipient: ContractAddress,
        permitted_minter: ContractAddress,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
    ) {
        // Initialize ERC20
        self.erc20.initializer(:name, :symbol);
        self._set_decimals(decimals);

        // Mint initial supply if any
        if initial_supply > 0 {
            self.erc20.mint(:recipient, amount: initial_supply);
        }

        // Initialize permitted minter
        assert(permitted_minter.is_non_zero(), Errors::INVALID_MINTER);
        self.permitted_minter.write(permitted_minter);

        // Initialize roles
        self.roles.initialize(:governance_admin);

        // Initialize replaceability
        self.replaceability.initialize(:upgrade_delay);
    }


    // Custom decimals implementation
    #[abi(embed_v0)]
    impl ERC20MetadataImpl of IERC20Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc20.ERC20_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc20.ERC20_symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.ERC20_decimals.read()
        }
    }

    #[abi(embed_v0)]
    pub impl MintableTokenImpl of IMintableToken<ContractState> {
        fn permissioned_mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.only_minter();
            self.erc20.mint(recipient: account, :amount);
        }

        fn permissioned_burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.only_minter();
            self.erc20.burn(:account, :amount);
        }

        fn is_permitted_minter(self: @ContractState, account: ContractAddress) -> bool {
            account == self.permitted_minter.read()
        }
    }

    // Allowance helpers (snake_case)
    #[external(v0)]
    fn increase_allowance(
        ref self: ContractState, spender: ContractAddress, added_value: u256,
    ) -> bool {
        self._increase_allowance(:spender, :added_value)
    }

    #[external(v0)]
    fn decrease_allowance(
        ref self: ContractState, spender: ContractAddress, subtracted_value: u256,
    ) -> bool {
        self._decrease_allowance(:spender, :subtracted_value)
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _set_decimals(ref self: ContractState, decimals: u8) {
            self.ERC20_decimals.write(decimals);
        }

        fn only_minter(self: @ContractState) {
            assert(get_caller_address() == self.permitted_minter.read(), Errors::ONLY_MINTER);
        }

        fn _increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256,
        ) -> bool {
            let caller = get_caller_address();
            let current_allowance = self.erc20.allowance(owner: caller, :spender);
            self.erc20._approve(owner: caller, :spender, amount: current_allowance + added_value);
            true
        }

        fn _decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256,
        ) -> bool {
            let caller = get_caller_address();
            let current_allowance = self.erc20.allowance(owner: caller, :spender);
            self
                .erc20
                ._approve(owner: caller, :spender, amount: current_allowance - subtracted_value);
            true
        }
    }
}
