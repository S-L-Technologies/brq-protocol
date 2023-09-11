// common
mod upgradeable;
mod utils;
mod types;
mod felt_math;
mod cumulative_balance;

mod world_config;

mod migrate;

mod set_nft;

mod erc1155;
mod briq_token;
mod box_nft;

mod attributes;

mod briq_factory {
    mod components;
    mod systems;
    mod constants;
}


#[cfg(test)]
mod tests;
