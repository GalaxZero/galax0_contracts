use starknet::ContractAddress;

// Core data structures for financial data
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct WalletData {
    pub balance: u256,
    pub transaction_count: u256,
    pub first_transaction_time: u64,
    pub last_transaction_time: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct DefiData {
    pub total_value_locked: u256,
    pub protocol_interactions: u256,
    pub unique_protocols: u256,
    pub first_interaction: u64,
    pub last_interaction: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ExchangeData {
    pub trading_volume: u256,
    pub successful_trades: u256,
    pub failed_trades: u256,
    pub liquidations: u256,
    pub first_trade: u64,
    pub last_trade: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CreditScore {
    pub score: u256,
    pub last_update: u64,
    pub confidence_level: u8,  // 1-100
    pub data_completeness: u8, // 1-100
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ScoreFactors {
    pub wallet_weight: u8,      // Base wallet activity
    pub defi_weight: u8,        // DeFi participation
    pub exchange_weight: u8,    // Trading activity
    pub longevity_weight: u8,   // Account age
    pub stability_weight: u8,   // Consistency of activity
}

#[derive(Copy, Drop, Serde)]
pub struct VerificationData {
    pub data_hash: felt252,     // Hash of all input data
    pub verification_time: u64,
    pub verifier: ContractAddress,
}

// Access control for score sharing
#[derive(Copy, Drop, Serde, starknet::Store )]
pub struct ScoringPermission {
    pub granted_to: ContractAddress,
    pub granted_by: ContractAddress,
    pub permission_type: u8,    // 1: View Score, 2: View Details, 3: Full Access
    pub expiry: u64,
}

// Constants
pub mod Constants {
    pub const MIN_SCORE: u256 = 300;
    pub const MAX_SCORE: u256 = 850;
    
    pub const ADMIN_ROLE: felt252 = 'ADMIN_ROLE';
    pub const VERIFIER_ROLE: felt252 = 'VERIFIER_ROLE';
    pub const DATA_PROVIDER_ROLE: felt252 = 'DATA_PROVIDER_ROLE';
    
    // Score weights (total should be 100)
    pub const WALLET_WEIGHT: u8 = 30;
    pub const DEFI_WEIGHT: u8 = 25;
    pub const EXCHANGE_WEIGHT: u8 = 20;
    pub const LONGEVITY_WEIGHT: u8 = 15;
    pub const STABILITY_WEIGHT: u8 = 10;

    // Minimum requirements
    pub const MIN_ACCOUNT_AGE_DAYS: u64 = 30;
    pub const MIN_TRANSACTIONS: u256 = 5;
    pub const MIN_DEFI_INTERACTIONS: u256 = 2;
}

// Errors as constants for consistent error handling
pub mod Errors {
    pub const INSUFFICIENT_PERMISSION: felt252 = 'NO_PERMISSION';
    pub const INVALID_PARAMETERS: felt252 = 'INVALID_PARAMS';
    pub const SYSTEM_PAUSED: felt252 = 'SYSTEM_PAUSED';
    pub const ALREADY_INITIALIZED: felt252 = 'ALREADY_INITIALIZED';
    pub const INVALID_STATE: felt252 = 'INVALID_STATE';
    pub const INSUFFICIENT_DATA: felt252 = 'INSUFFICIENT_DATA';
    pub const SCORE_NOT_FOUND: felt252 = 'SCORE_NOT_FOUND';
    pub const INVALID_TIMEFRAME: felt252 = 'INVALID_TIMEFRAME';
    pub const RATE_LIMIT_EXCEEDED: felt252 = 'RATE_LIMIT_EXCEEDED';
}