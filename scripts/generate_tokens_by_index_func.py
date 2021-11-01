items = 100

out = """
# Autogenerated, see scripts/generate_tokens_by_index_func.py
@view
func tokens_at_index{
        pedersen_ptr: HashBuiltin*,
        syscall_ptr: felt*,
        range_check_ptr
    } (owner: felt, index: felt) -> (
""" + "\n".join([f"        ret{i}: felt,  rMat{i}: felt, rSet{i}: felt," for i in range(items)]) + f"""
    ):
    alloc_locals
    let (res) = balances.read(owner=owner)
    assert_lt(index*{items}, res)
""" + "\n".join([f"    let(local retval{i}: felt) = balance_details.read(owner=owner, index=index*{items}+{i})" for i in range(items)]) + """
""" + "\n".join([f"    let(local retMat{i}: felt) = material.read(token_id=retval{i})" for i in range(items)]) + """
""" + "\n".join([f"    let(local retSet{i}: felt) = part_of_set.read(token_id=retval{i})" for i in range(items)]) + """
    return (
""" + "\n".join([f"        ret{i}=retval{i}, rMat{i}=retMat{i}, rSet{i}=retSet{i}," for i in range(items)]) + """
    )
end
"""

print(out)