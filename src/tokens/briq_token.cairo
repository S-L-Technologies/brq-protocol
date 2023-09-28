#[starknet::contract]
mod BriqToken {
    use briq_protocol::erc::erc1155::components::{
        ERC1155OperatorApproval, ERC1155Balance,
        increase_balance as increase_balance_1155, decrease_balance as decrease_balance_1155
    };
    use briq_protocol::erc::get_world::GetWorldTrait;
    use briq_protocol::erc::erc1155::internal_trait::InternalTrait1155;
    use briq_protocol::cumulative_balance::{CUM_BALANCE_TOKEN, CB_BRIQ};
    use dojo_erc::token::erc1155::interface;
    use dojo_erc::token::erc1155::interface::{IERC1155, IERC1155CamelOnly};
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address};
    use array::ArrayTCloneImpl;
    use zeroable::Zeroable;
    use debug::PrintTrait;

    #[storage]
    struct Storage {
        _world: ContractAddress,
    }

    #[event]
    #[derive(Clone, Drop, starknet::Event)]
    enum Event {
        TransferSingle: TransferSingle,
        TransferBatch: TransferBatch,
        ApprovalForAll: ApprovalForAll
    }

    #[derive(Clone, Drop, starknet::Event)]
    struct TransferSingle {
        operator: ContractAddress,
        from: ContractAddress,
        to: ContractAddress,
        id: u256,
        value: u256
    }

    #[derive(Clone, Drop, starknet::Event)]
    struct TransferBatch {
        operator: ContractAddress,
        from: ContractAddress,
        to: ContractAddress,
        ids: Array<u256>,
        values: Array<u256>
    }

    #[derive(Clone, Drop, starknet::Event)]
    struct ApprovalForAll {
        owner: ContractAddress,
        operator: ContractAddress,
        approved: bool
    }

    mod Errors {
        const INVALID_TOKEN_ID: felt252 = 'ERC1155: invalid token ID';
        const INVALID_ACCOUNT: felt252 = 'ERC1155: invalid account';
        const UNAUTHORIZED: felt252 = 'ERC1155: unauthorized caller';
        const SELF_APPROVAL: felt252 = 'ERC1155: self approval';
        const INVALID_RECEIVER: felt252 = 'ERC1155: invalid receiver';
        const WRONG_SENDER: felt252 = 'ERC1155: wrong sender';
        const SAFE_MINT_FAILED: felt252 = 'ERC1155: safe mint failed';
        const SAFE_TRANSFER_FAILED: felt252 = 'ERC1155: safe transfer failed';
        const INVALID_ARRAY_LENGTH: felt252 = 'ERC1155: invalid array length';
        const INSUFFICIENT_BALANCE: felt252 = 'ERC1155: insufficient balance';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        world: ContractAddress
    ) {
        self._world.write(world);
    }

    //
    // External
    //

    // #[external(v0)]
    // impl SRC5Impl of ISRC5<ContractState> {
    //     fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
    //         let unsafe_state = src5::SRC5::unsafe_new_contract_state();
    //         src5::SRC5::SRC5Impl::supports_interface(@unsafe_state, interface_id)
    //     }
    // }

    // #[external(v0)]
    // impl SRC5CamelImpl of ISRC5Camel<ContractState> {
    //     fn supportsInterface(self: @ContractState, interfaceId: felt252) -> bool {
    //         let unsafe_state = src5::SRC5::unsafe_new_contract_state();
    //         src5::SRC5::SRC5CamelImpl::supportsInterface(@unsafe_state, interfaceId)
    //     }
    // }

    use briq_protocol::world_config::{get_world_config, AdminTrait};
    #[external(v0)]
    impl MintBurnBriqs of briq_protocol::erc::mint_burn::MintBurn<ContractState> {
        fn mint(ref self: ContractState, owner: ContractAddress, token_id: felt252, amount: u128) {
            if !self.world().is_admin(@get_caller_address()) {
                if get_world_config(self.world()).factory != get_caller_address() {
                    assert(self.world().is_box_contract(get_caller_address()), Errors::UNAUTHORIZED);
                }
            }
            self._mint(owner, token_id.into(), amount.into())
        }
        fn burn(ref self: ContractState, owner: ContractAddress, token_id: felt252, amount: u128) {
            self.world().only_admins(@get_caller_address());
            self._burn(token_id.into(), amount.into())
        }
    }

    #[external(v0)]
    impl ERC1155MetadataImpl of interface::IERC1155Metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            'briq token'
        }

        fn symbol(self: @ContractState) -> felt252 {
            'BRIQ'
        }

        fn uri(self: @ContractState, token_id: u256) -> felt252 {
            //assert(self._exists(token_id), Errors::INVALID_TOKEN_ID);
            // TODO : concat with id
            ''
        }
    }

    #[external(v0)]
    impl ERC1155Impl of interface::IERC1155<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress, id: u256) -> u256 {
            assert(account.is_non_zero(), Errors::INVALID_ACCOUNT);
            self.get_balance(account, id)
        }

        fn balance_of_batch(
            self: @ContractState, accounts: Array<ContractAddress>, ids: Array<u256>
        ) -> Array<u256> {
            assert(ids.len() == accounts.len(), Errors::INVALID_ARRAY_LENGTH);

            let mut batch_balances = array![];
            let mut index = 0;
            loop {
                if index == ids.len() {
                    break batch_balances.clone();
                }
                batch_balances.append(self.balance_of(*accounts.at(index), *ids.at(index)));
                index += 1;
            }
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self._set_approval_for_all(get_caller_address(), operator, approved)
        }

        fn is_approved_for_all(
            self: @ContractState, account: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.get_operator_approval(account, operator).approved
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Array<u8>
        ) {
            assert(to.is_non_zero(), Errors::INVALID_RECEIVER);
            assert(from.is_non_zero(), Errors::WRONG_SENDER);
            assert(
                self._is_approved_for_all_or_owner(from, get_caller_address()), Errors::UNAUTHORIZED
            );

            self._safe_transfer_from(from, to, id, amount, data);
        }

        fn safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Array<u8>
        ) {
            assert(to.is_non_zero(), Errors::INVALID_RECEIVER);
            assert(from.is_non_zero(), Errors::WRONG_SENDER);
            assert(
                self._is_approved_for_all_or_owner(from, get_caller_address()), Errors::UNAUTHORIZED
            );

            self._safe_batch_transfer_from(from, to, ids, amounts, data);
        }
    }

    #[external(v0)]
    impl ERC1155CamelOnlyImpl of interface::IERC1155CamelOnly<ContractState> {
        fn balanceOf(self: @ContractState, account: ContractAddress, id: u256) -> u256 {
            ERC1155Impl::balance_of(self, account, id)
        }

        fn balanceOfBatch(
            self: @ContractState, accounts: Array<ContractAddress>, ids: Array<u256>
        ) -> Array<u256> {
            ERC1155Impl::balance_of_batch(self, accounts, ids)
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            ERC1155Impl::set_approval_for_all(ref self, operator, approved);
        }
        fn isApprovedForAll(
            self: @ContractState, account: ContractAddress, operator: ContractAddress
        ) -> bool {
            ERC1155Impl::is_approved_for_all(self, account, operator)
        }
        fn safeTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Array<u8>
        ) {
            ERC1155Impl::safe_transfer_from(ref self, from, to, id, amount, data);
        }
        fn safeBatchTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Array<u8>
        ) {
            ERC1155Impl::safe_batch_transfer_from(ref self, from, to, ids, amounts, data);
        }
    }

    //
    // Internal
    //

    impl GetWorldImpl of GetWorldTrait<ContractState> {
        fn world(self: @ContractState) -> IWorldDispatcher {
            IWorldDispatcher { contract_address: self._world.read() }
        }
    }

    #[generate_trait]
    impl WorldInteractionsImpl of WorldInteractionsTrait {
        fn get_balance(self: @ContractState, account: ContractAddress, id: u256) -> u256 {
            get!(self.world(), (get_contract_address(), account, TryInto::<u256, felt252>::try_into(id).unwrap()), ERC1155Balance).amount.into()
        }

        fn get_operator_approval(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> ERC1155OperatorApproval {
            get!(self.world(), (get_contract_address(), owner, operator), ERC1155OperatorApproval)
        }

        fn set_operator_approval(
            ref self: ContractState,
            owner: ContractAddress,
            operator: ContractAddress,
            approved: bool
        ) {
            set!(
                self.world(),
                ERC1155OperatorApproval { token: get_contract_address(), owner, operator, approved }
            );
            self.emit_event(ApprovalForAll { owner, operator, approved });
        }

        fn set_balance(ref self: ContractState, account: ContractAddress, id: u256, amount: u256) {
            set!(
                self.world(), ERC1155Balance { token: get_contract_address(), account, id: TryInto::<u256, felt252>::try_into(id).unwrap(), amount: amount.try_into().unwrap() }
            );
        }

        fn update_balances(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
        ) {
            // WARNING: briq delta
            if self.get_balance(to, id) == 0 && amount > 0 {
                increase_balance_1155(self.world(), CUM_BALANCE_TOKEN(), to, CB_BRIQ(), 1);
            }
            self.set_balance(from, id, self.get_balance(from, id) - amount);
            self.set_balance(to, id, self.get_balance(to, id) + amount);
            if self.get_balance(from, id) == 0 && amount > 0 {
                decrease_balance_1155(self.world(), CUM_BALANCE_TOKEN(), from, CB_BRIQ(), 1);
            }
        }

        fn emit_event<
            S, impl IntoImp: traits::Into<S, Event>, impl SDrop: Drop<S>, impl SClone: Clone<S>
        >(
            ref self: ContractState, event: S
        ) {
            self.emit(event.clone());
            emit!(self.world(), event);
        }
    }

    impl InternalImpl of InternalTrait1155<ContractState> {
        fn _is_approved_for_all_or_owner(
            self: @ContractState, from: ContractAddress, caller: ContractAddress
        ) -> bool {
            // WARNING: briq delta
            if !(caller == from || self.is_approved_for_all(from, caller)) {
                return self.world().is_set_contract(get_caller_address());
            }
            false
        }

        fn _set_approval_for_all(
            ref self: ContractState,
            owner: ContractAddress,
            operator: ContractAddress,
            approved: bool
        ) {
            assert(owner != operator, Errors::SELF_APPROVAL);
            self.set_operator_approval(owner, operator, approved);
        }

        fn _safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Array<u8>
        ) {
            self.update_balances(from, to, id, amount);
            // assert(
            //     _check_on_erc1155_received(from, to, id, data), Errors::SAFE_TRANSFER_FAILED
            // );

            self
                .emit_event(
                    TransferSingle { operator: get_caller_address(), from, to, id, value: amount }
                );
        }

        fn _safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Array<u8>
        ) {
            assert(ids.len() == amounts.len(), Errors::INVALID_ARRAY_LENGTH);

            let mut ids_span = ids.span();
            let mut amounts_span = amounts.span();

            loop {
                if ids_span.len() == 0 {
                    break ();
                }
                let id = *ids_span.pop_front().unwrap();
                let amount = *amounts_span.pop_front().unwrap();
                self.update_balances(from, to, id, amount);
            // assert(
            //     _check_on_erc1155_received(from, to, id, data), Errors::SAFE_TRANSFER_FAILED
            // );
            };

            self
                .emit_event(
                    TransferBatch { operator: get_caller_address(), from, to, ids, values: amounts }
                );
        }

        fn _mint(ref self: ContractState, to: ContractAddress, id: u256, amount: u256) {
            assert(to.is_non_zero(), Errors::INVALID_RECEIVER);

            self.set_balance(to, id, self.get_balance(to, id) + amount);

            self
                .emit_event(
                    TransferSingle {
                        operator: get_caller_address(),
                        from: Zeroable::zero(),
                        to,
                        id,
                        value: amount
                    }
                );
        }

        fn _burn(ref self: ContractState, id: u256, amount: u256) {
            let caller = get_caller_address();
            assert(self.get_balance(caller, id) >= amount, Errors::INSUFFICIENT_BALANCE);

            self.set_balance(caller, id, self.get_balance(caller, id) - amount);

            self
                .emit_event(
                    TransferSingle {
                        operator: get_caller_address(),
                        from: caller,
                        to: Zeroable::zero(),
                        id,
                        value: amount
                    }
                );
        }

        fn _safe_mint(
            ref self: ContractState,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Span<felt252>
        ) {
            self._mint(to, id, amount);
        // assert(
        //     _check_on_erc1155_received(Zeroable::zero(), to, id, data),
        //     Errors::SAFE_MINT_FAILED
        // );
        }
    }
//#[internal]
// fn _check_on_erc1155_received(
//     from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
// ) -> bool {
//     if (DualCaseSRC5 { contract_address: to }
//         .supports_interface(interface::IERC1155_RECEIVER_ID)) {
//         DualCaseERC1155Receiver { contract_address: to }
//             .on_erc1155_received(
//                 get_caller_address(), from, token_id, data
//             ) == interface::IERC1155_RECEIVER_ID
//     } else {
//         DualCaseSRC5 { contract_address: to }.supports_interface(account::interface::ISRC6_ID)
//     }
// }

}