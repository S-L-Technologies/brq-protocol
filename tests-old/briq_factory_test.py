from types import SimpleNamespace
import pytest
import pytest_asyncio

from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.business_logic.state.state_api_objects import BlockInfo

from .conftest import declare, declare_and_deploy, proxy_contract, compile

ADDRESS = 0xcafe
OTHER_ADDRESS = 0xfade
DISALLOWED_ADDRESS = 0xdead


@pytest_asyncio.fixture(scope="session")
async def factory_root():
    starknet = await Starknet.empty()

    [briq_factory, _] = await declare_and_deploy(starknet, "briq_factory.cairo")

    return (starknet, briq_factory)


@pytest_asyncio.fixture
async def factory(factory_root):
    [starknet, briq_factory] = factory_root
    state = Starknet(state=starknet.state.copy())
    return SimpleNamespace(
        starknet=state,
        briq_factory=proxy_contract(state, briq_factory),
    )

import matplotlib.pyplot as plt


@pytest.mark.asyncio
async def test_chart(factory):
    await factory.briq_factory.initialise(0, 0, 0).execute()

    xs = [t for t in range(300000, 600000, 300000 // 100)]
    ys = [(await factory.briq_factory.get_price_at_t(t * 10**18, 1).call()).result.price / 10**18 for t in xs]
    ys2 = [(await factory.briq_factory.get_price_at_t(t * 10**18, 200).call()).result.price / 10**18 for t in xs]

    # Create a figure and a set of subplots
    fig, ax = plt.subplots()

    # Plot data
    ax.plot(xs, ys)
    ax.plot(xs, ys2)

    # Set labels for x and y axis
    ax.set_xlabel('X values')
    ax.set_ylabel('Y values')

    # Set a title for the plot
    ax.set_title('A simple line plot')

    # Display the plot
    plt.show()


slope = 1 * 10**8
raw_floor = -1 * 10**13

lower_floor = 1 * 10**13
lower_slope = 5 * 10**7

decay_per_second = 6337791082068820

inflection_point = 400000

def price_below_ip(t, amount):
    return (lower_floor + (lower_slope * t + lower_slope * (t + amount)) // 2) * amount

def price_above_ip(t, amount):
    return (raw_floor + (slope * t + slope * (t + amount)) // 2) * amount


@pytest.mark.asyncio
async def test_integrate(factory):
    await factory.briq_factory.initialise(0, 0, 0).execute()
    assert (await factory.briq_factory.get_current_t().call()).result.t == 0

    assert (await factory.briq_factory.get_price(1).call()).result.price == lower_floor + lower_slope / 2
    expected_price = price_below_ip(0, 1000)
    assert (await factory.briq_factory.get_price(1000).call()).result.price == expected_price

    await factory.briq_factory.initialise(1000 * 10**18, 0, 0).execute()
    assert (await factory.briq_factory.get_current_t().call()).result.t == 1000 * 10**18

    # Test above inflection point.
    await factory.briq_factory.initialise(inflection_point * 10 ** 18, 0, 0).execute()
    expected_price = price_above_ip(inflection_point, 1000)
    assert expected_price == 0.03005 * 10**18
    assert (await factory.briq_factory.get_price(1000).call()).result.price == expected_price

    factory.starknet.state.state.update_block_info(
        BlockInfo.create_for_testing(
            block_number=3,
            block_timestamp=10000
        )
    )
    assert (await factory.briq_factory.get_current_t().call()).result.t == inflection_point * 10**18 - decay_per_second * 10000

    factory.starknet.state.state.update_block_info(
        BlockInfo.create_for_testing(
            block_number=4,
            block_timestamp=3600 * 24 * 365 * 5
        )
    )
    assert (await factory.briq_factory.get_current_t().call()).result.t == 0
    assert (await factory.briq_factory.get_surge_t().call()).result.t == 0


@pytest.mark.asyncio
async def test_inflection_point(factory):
    await factory.briq_factory.initialise((inflection_point - 100000) * 10**18, 0, 0).execute()

    lower_ppb = lower_floor + (lower_slope * 300000 + lower_slope * 400000) / 2
    assert (await factory.briq_factory.get_price(100000).call()).result.price == lower_ppb * 100000

    higher_ppb = raw_floor + (slope * inflection_point + slope * (inflection_point + 100000)) // 2
    expected_price = 100000 * lower_ppb + 100000 * higher_ppb
    assert (await factory.briq_factory.get_price(200000).call()).result.price == expected_price


@pytest.mark.asyncio
async def test_overflows(factory):
    # Try wuth the maximum value I allow and ensure that we don't get overflows.
    await factory.briq_factory.initialise(10**18 * (10**12 - 1), 0, 0).execute()
    assert (await factory.briq_factory.get_price(1).call()).result.price == price_above_ip((10**12 - 1), 1)

    base = price_above_ip((10**12 - 1), 10**10 - 1)
    surge_amount = 10**10 - 1 - 250000
    surge_p = 10**8 * surge_amount * surge_amount // 2
    assert (await factory.briq_factory.get_price(10**10 - 1).call()).result.price == base + surge_p


@pytest.mark.asyncio
async def test_surge(factory):
    await factory.briq_factory.initialise(0, 0, 0).execute()
    assert (await factory.briq_factory.get_price(1).call()).result.price == price_below_ip(0, 1)

    await factory.briq_factory.initialise(0, 250000 * 10**18, 0).execute()
    assert (await factory.briq_factory.get_price(1).call()).result.price == price_below_ip(0, 1) + 10**8 / 2

    await factory.briq_factory.initialise(0, 0, 0).execute()
    assert (await factory.briq_factory.get_price(250000).call()).result.price == price_below_ip(0, 250000)

    await factory.briq_factory.initialise(0, 0, 0).execute()
    assert (await factory.briq_factory.get_price(250001).call()).result.price == price_below_ip(0, 250001) + 10**8 // 2

    await factory.briq_factory.initialise(0, 200000 * 10**18, 0).execute()
    assert (await factory.briq_factory.get_price(100000).call()).result.price == price_below_ip(0, 100000) + 10**8 * 50000 * 50000 // 2

    await factory.briq_factory.initialise(0, 250000 * 10**18, 0).execute()
    assert (await factory.briq_factory.get_surge_t().call()).result.t == 250000 * 10**18

    factory.starknet.state.state.update_block_info(
        BlockInfo.create_for_testing(
            block_number=3,
            block_timestamp=3600 * 24 * 3
        )
    )

    # Has about halved in half a week
    assert 250000 * 10**18 - 4134 * 10**14 * 3600 * 24 * 3 < 250000 * 10**18 * 3 / 5
    assert (await factory.briq_factory.get_surge_t().call()).result.t == 250000 * 10**18 - 4134 * 10**14 * 3600 * 24 * 3

    factory.starknet.state.state.update_block_info(
        BlockInfo.create_for_testing(
            block_number=3,
            block_timestamp=3600 * 24 * 12
        )
    )

    assert (await factory.briq_factory.get_surge_t().call()).result.t == 0


@pytest.mark.asyncio
async def test_actual(factory):

    erc20 = compile("vendor/openzeppelin/token/erc20/presets/ERC20Mintable.cairo")
    await factory.starknet.declare(contract_class=erc20)
    token_contract_eth = await factory.starknet.deploy(contract_class=erc20, constructor_calldata=[
        0x1,  # name: felt,
        0x1,  # symbol: felt,
        18,  # decimals: felt,
        0, 2 * 64,  # initial_supply: Uint256,
        ADDRESS,  # recipient: felt,
        ADDRESS  # owner: felt
    ])

    [briq_contract, _] = await declare_and_deploy(factory.starknet, "briq.cairo")

    await factory.briq_factory.initialise(0, 0, token_contract_eth.contract_address).execute()
    await factory.briq_factory.setBriqAddress_(briq_contract.contract_address).execute()

    await briq_contract.setFactoryAddress_(factory.briq_factory.contract_address).execute()

    with pytest.raises(StarkException, match="insufficient allowance"):
        await factory.briq_factory.buy(1000).execute(ADDRESS)

    await token_contract_eth.approve(factory.briq_factory.contract_address, (10**18, 0)).execute(ADDRESS)
    await factory.briq_factory.buy(1000).execute(ADDRESS)
