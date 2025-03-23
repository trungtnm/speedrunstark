use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<T> {
    // Core functions
    fn execute(ref self: T);
    fn stake(ref self: T, amount: u256);
    fn withdraw(ref self: T);
    // Getters
    fn balances(self: @T, account: ContractAddress) -> u256;
    fn completed(self: @T) -> bool;
    fn deadline(self: @T) -> u64;
    fn example_external_contract(self: @T) -> ContractAddress;
    fn open_for_withdraw(self: @T) -> bool;
    fn eth_token_dispatcher(self: @T) -> IERC20CamelDispatcher;
    fn threshold(self: @T) -> u256;
    fn total_balance(self: @T) -> u256;
    fn time_left(self: @T) -> u64;
}

#[starknet::contract]
pub mod Staker {
    use contracts::ExampleExternalContract::{
        IExampleExternalContractDispatcher, IExampleExternalContractDispatcherTrait,
    };
    use starknet::storage::Map;
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};
    use super::{ContractAddress, IERC20CamelDispatcher, IERC20CamelDispatcherTrait, IStaker};

    const THRESHOLD: u256 = 1000000000000000000; // ONE_ETH_IN_WEI: 10 ^ 18;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Stake: Stake,
    }

    #[derive(Drop, starknet::Event)]
    struct Stake {
        #[key]
        sender: ContractAddress,
        amount: u256,
    }

    #[storage]
    struct Storage {
        eth_token_dispatcher: IERC20CamelDispatcher,
        balances: Map<ContractAddress, u256>,
        total_staked: u256,
        deadline: u64,
        open_for_withdraw: bool,
        external_contract_address: ContractAddress,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        eth_contract: ContractAddress,
        external_contract_address: ContractAddress,
    ) {
        self.eth_token_dispatcher.write(IERC20CamelDispatcher { contract_address: eth_contract });
        self.external_contract_address.write(external_contract_address);
        // ToDo Checkpoint 2: Set the deadline to 60 seconds from now. Implement your code here.
        self.deadline.write(get_block_timestamp() + 60);
    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
        // ToDo Checkpoint 1: Implement your `stake` function here
        fn stake(
            ref self: ContractState, amount: u256,
        ) { 
            // assert that ExternalContract is not completed
            self.not_completed();

            // Ensure the staking period is still open
            let deadline = self.deadline.read();
            let current_time = get_block_timestamp();
            assert(current_time <= deadline, 0x1); // ERROR CODE 0x1
            
            // Check if the user has approved the staking contract to spend the amount
            let sender = get_caller_address();
            let contract = get_contract_address();
            let token_dispatcher = self.eth_token_dispatcher.read();
            let allowance = token_dispatcher.allowance(sender, contract);
            assert(allowance >= amount, 0x2); // ERROR CODE 0x2

            // Transfer the staked amount from sender to this contract
            token_dispatcher.transferFrom(sender, contract, amount);

            // Update sender's staked balance
            let current_sender_balance = self.balances.read(sender);
            let new_sender_balance = current_sender_balance + amount;
            self.balances.write(sender, new_sender_balance);

            // update total staked amount
            let current_total_staked = self.total_staked.read();
            let new_total_staked = current_total_staked + amount;
            self.total_staked.write(new_total_staked);

            // Emit the stake event
            self.emit(Stake { sender, amount });
        }

        // Function to execute the transfer or allow withdrawals after the deadline
        // ToDo Checkpoint 2: Implement your `execute` function here
        // In this implimentation, we should call the `complete_transfer` function if the staked
        // amount is greater than or equal to the threshold Otherwise, we should call
        // `open_for_withdraw` function ToDo Checkpoint 3: Assert that the staking period has ended
        // ToDo Checkpoint 3: Protect the function calling `not_completed` function before the
        // execution
        fn execute(ref self: ContractState) {
            // ensure that ExternalContract is not completed
            self.not_completed();

            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();

            // Ensure the staking period has ended
            assert(current_time >= deadline, 0x3); // ERROR CODE 0x3

            // we should not use ERC20 balanceOf() to get the total staked amount
            // because there is a case that people transfer ETH directly to the contract, which will not be tracked by our Staker Contract
            // let staked_amount = self.eth_token_dispatcher.read().balanceOf(get_contract_address());
            let staked_amount = self.total_staked.read();

            if (staked_amount >= THRESHOLD) {
                self.complete_transfer(staked_amount);
            } else {
                self.open_for_withdraw.write(true);
            }
        }

        // ToDo Checkpoint 3: Implement your `withdraw` function here
        fn withdraw(ref self: ContractState) {
            // check if we open for withdraw
            assert(self.open_for_withdraw.read(), 0x5); // ERROR CODE 0x5
            self.not_completed();

            let sender = get_caller_address();
            let user_balance = self.balances.read(sender);
            assert(user_balance > 0, 0x6); // ERROR CODE 0x6
            
            // transfer token to user and reset staked amount
            let token_dispatcher = self.eth_token_dispatcher.read();
            self.balances.write(sender, 0);
            token_dispatcher.transfer(sender, user_balance);
            
            // update total staked amount
            let current_total_staked = self.total_staked.read();
            let new_total_staked = current_total_staked - user_balance;
            self.total_staked.write(new_total_staked);
        }

        fn balances(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn total_balance(self: @ContractState) -> u256 {
            self.total_staked.read()
        }

        fn deadline(self: @ContractState) -> u64 {
            self.deadline.read()
        }

        fn threshold(self: @ContractState) -> u256 {
            THRESHOLD
        }

        fn eth_token_dispatcher(self: @ContractState) -> IERC20CamelDispatcher {
            self.eth_token_dispatcher.read()
        }

        fn open_for_withdraw(self: @ContractState) -> bool {
            self.open_for_withdraw.read()
        }

        fn example_external_contract(self: @ContractState) -> ContractAddress {
            self.external_contract_address.read()
        }
        // Read Function to check if the external contract is completed.
        // ToDo Checkpoint 3: Implement your completed function here
        fn completed(self: @ContractState) -> bool {
            let external_contract_address = self.external_contract_address.read();
            let external_contract = IExampleExternalContractDispatcher { contract_address: external_contract_address };

            external_contract.completed()
        }
        // ToDo Checkpoint 2: Implement your time_left function here
        fn time_left(self: @ContractState) -> u64 {
            let deadline = self.deadline.read();
            let now = get_block_timestamp();
            if (now >= deadline) {
                // return 0 if the deadline has passed
                0
            } else {
                 // return timeleft
                 deadline - now
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // ToDo Checkpoint 2: Implement your complete_transfer function here
        // This function should be called after the deadline has passed and the staked amount is
        // greater than or equal to the threshold You have to call/use this function in the above
        // `execute` function This function should call the `complete` function of the external
        // contract and transfer the staked amount to the external contract
        fn complete_transfer(
            ref self: ContractState, amount: u256,
        ) { 
            // Note: Staker contract should approve to transfer the staked_amount to the external contract
            let external_contract_address = self.external_contract_address.read();
            let token_contract_dispatch = self.eth_token_dispatcher.read();
            
            // token transfer
            token_contract_dispatch.transfer(external_contract_address, amount);
            let external_contract = IExampleExternalContractDispatcher { contract_address: external_contract_address };
            external_contract.complete()

        }
        // ToDo Checkpoint 3: Implement your not_completed function here
        fn not_completed(ref self: ContractState) {
            // since the function signature does not have a return type, so i will make an assert
            let external_contract_address = self.external_contract_address.read();
            let external_contract = IExampleExternalContractDispatcher { contract_address: external_contract_address };
            assert(!external_contract.completed(), 0x4);  // ERROR CODE 0x4
        }
    }
}
