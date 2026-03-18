#[starknet::contract]
pub mod token {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;
    use starkware_utils::byte_array::short_string_to_byte_array;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::interfaces::mintable_token::IMintableToken;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;
    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
    }

    const NAME: felt252 = 'strkBTC';
    const SYMBOL: felt252 = 'strkBTC';

    impl ImmutableConfigImpl of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 8;
    }

    #[constructor]
    fn constructor(ref self: ContractState, governance_admin: ContractAddress, upgrade_delay: u64) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self
            .erc20
            .initializer(
                name: short_string_to_byte_array(NAME), symbol: short_string_to_byte_array(SYMBOL),
            );
    }

    #[abi(embed_v0)]
    pub impl MintableTokenImpl of IMintableToken<ContractState> {
        fn permissioned_mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.roles.only_token_admin();
            self.erc20.mint(account, amount);
        }

        fn permissioned_burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.roles.only_token_admin();
            self.erc20.burn(account, amount);
        }

        fn is_permitted_minter(self: @ContractState, account: ContractAddress) -> bool {
            self.roles.is_token_admin(:account)
        }
    }
}
