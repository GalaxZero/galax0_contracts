#[cfg(test)]
use starknet::ContractAddress;
use snforge_std::declare;
use snforge_std::{start_prank, stop_prank};
use core::array::ArrayTrait;
use galax0_contracts::data_structures::{
    WalletData, DefiData, ExchangeData,
    Constants
};
use galax0_contracts::data_provider::{IDataProviderDispatcher, IDataProviderDispatcherTrait};
use galax0_contracts::scoring_engine::{IScoringEngineDispatcher, IScoringEngineDispatcherTrait};
use galax0_contracts::main::{ICreditScoreMainDispatcher, ICreditScoreMainDispatcherTrait};

// Helper function to deploy contracts
fn deploy_contracts() -> (ContractAddress, ContractAddress, ContractAddress) {
    // Deploy Data Provider
    let data_provider_contract = declare('DataProvider');
    let admin_address = starknet::contract_address_const::<0x123>();
    let mut calldata = ArrayTrait::new();
    calldata.append(admin_address.into());
    let data_provider_address = data_provider_contract.deploy(@calldata).unwrap();

    // Deploy Scoring Engine
    let scoring_engine_contract = declare('ScoringEngine');
    let mut calldata = ArrayTrait::new();
    calldata.append(admin_address.into());
    let scoring_engine_address = scoring_engine_contract.deploy(@calldata).unwrap();

    // Deploy Main Contract
    let main_contract = declare('CreditScoreMain');
    let mut calldata = ArrayTrait::new();
    calldata.append(admin_address.into());
    calldata.append(scoring_engine_address.into());
    calldata.append(data_provider_address.into());
    let main_contract_address = main_contract.deploy(@calldata).unwrap();

    (data_provider_address, scoring_engine_address, main_contract_address)
}
// Helper function to create sample data
fn get_sample_data() -> (WalletData, DefiData, ExchangeData) {
    let wallet_data = WalletData {
        balance: 10_000_000_000_000_000_000_u256, // 10 ETH
        transaction_count: 100_u256,
        first_transaction_time: 1600000000,
        last_transaction_time: 1700000000,
    };

    let defi_data = DefiData {
        total_value_locked: 5_000_000_000_000_000_000_u256, // 5 ETH
        protocol_interactions: 50_u256,
        unique_protocols: 5_u256,
        first_interaction: 1600000100,
        last_interaction: 1700000100,
    };

    let exchange_data = ExchangeData {
        trading_volume: 100_000_000_000_000_000_000_u256, // 100 ETH
        successful_trades: 90_u256,
        failed_trades: 10_u256,
        liquidations: 1_u256,
        first_trade: 1600000200,
        last_trade: 1700000200,
    };

    (wallet_data, defi_data, exchange_data)
}

#[test]
fn test_data_provider_deployment() {
    let (data_provider_address, _, _) = deploy_contracts();
    assert!(data_provider_address != starknet::contract_address_const::<0>(), "Invalid contract address");
}

#[test]
fn test_data_submission() {
    let (data_provider_address, _, _) = deploy_contracts();
    let data_provider = IDataProviderDispatcher { contract_address: data_provider_address };
    let _admin_address = starknet::contract_address_const::<0x123>();
    
    // Set up test data
    let (wallet_data, defi_data, exchange_data) = get_sample_data();
    let user_address = starknet::contract_address_const::<0x456>();
    
    // Start admin prank
    start_prank(CheatTarget::One(data_provider_address), admin_address);
    
    // Submit data
    let wallet_result = data_provider.submit_wallet_data(user_address, wallet_data);
    let defi_result = data_provider.submit_defi_data(user_address, defi_data);
    let exchange_result = data_provider.submit_exchange_data(user_address, exchange_data);
    
    stop_prank(CheatTarget::One(data_provider_address));
    
    // Verify submission results
    assert!(wallet_result, "Wallet data submission failed");
    assert!(defi_result, "DeFi data submission failed");
    assert!(exchange_result, "Exchange data submission failed");
}

#[test]
fn test_scoring_engine() {
    let (_, scoring_engine_address, _) = deploy_contracts();
    let scoring_engine = IScoringEngineDispatcher { contract_address: scoring_engine_address };
    
    // Set up test data
    let (wallet_data, defi_data, exchange_data) = get_sample_data();
    
    // Calculate credit score
    let credit_score = scoring_engine.calculate_credit_score(wallet_data, defi_data, exchange_data);
    
    // Verify score is within valid range
    assert!(credit_score.score >= Constants::MIN_SCORE, "Score below minimum");
    assert!(credit_score.score <= Constants::MAX_SCORE, "Score above maximum");
    assert!(credit_score.confidence_level > 0, "Invalid confidence level");
}

#[test]
fn test_credit_score_main() {
    let (_, _, main_contract_address) = deploy_contracts();
    let main_contract = ICreditScoreMainDispatcher { contract_address: main_contract_address };
    
    // Set up test data
    let (wallet_data, defi_data, exchange_data) = get_sample_data();
    
    // Submit data and get score
    let submission_result = main_contract.submit_data(wallet_data, defi_data, exchange_data);
    assert!(submission_result, "Data submission failed");
    
    let credit_score = main_contract.get_credit_score();
    assert!(credit_score.score >= Constants::MIN_SCORE, "Score below minimum");
    assert!(credit_score.score <= Constants::MAX_SCORE, "Score above maximum");
}

#[test]
fn test_score_permissions() {
    let (_, _, main_contract_address) = deploy_contracts();
    let main_contract = ICreditScoreMainDispatcher { contract_address: main_contract_address };
    
    let viewer_address = starknet::contract_address_const::<0x789>();
    let permission_type: u8 = 1; // View Score permission
    
    // Grant permission
    main_contract.grant_score_access(viewer_address, permission_type);
    
    // Revoke permission
    main_contract.revoke_score_access(viewer_address);
}

#[test]
#[should_panic(expected: "INSUFFICIENT_PERMISSION")]
fn test_unauthorized_data_submission() {
    let (data_provider_address, _, _) = deploy_contracts();
    let data_provider = IDataProviderDispatcher { contract_address: data_provider_address };
    
    let (wallet_data, _, _) = get_sample_data();
    let user_address = starknet::contract_address_const::<0x456>();
    
    // Try to submit data without authorization (should fail)
    data_provider.submit_wallet_data(user_address, wallet_data);
}

#[test]
#[should_panic(expected: 'SYSTEM_PAUSED')]
fn test_paused_system() {
    let (_, _, main_contract_address) = deploy_contracts();
    let main_contract = ICreditScoreMainDispatcher { contract_address: main_contract_address };
    let _admin_address = starknet::contract_address_const::<0x123>();
    
    // Pause system as admin
    start_prank(CheatTarget::One(main_contract_address), admin_address);
    main_contract.pause();
    
    // Try to submit data while system is paused (should fail)
    let (wallet_data, defi_data, exchange_data) = get_sample_data();
    main_contract.submit_data(wallet_data, defi_data, exchange_data);
}