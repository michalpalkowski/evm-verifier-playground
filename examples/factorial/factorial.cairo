// Copyright 2023 StarkWare Industries Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License").
// You may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.starkware.co/open-source-license/
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions
// and limitations under the License.

%builtins output
func main(output_ptr: felt*) -> (output_ptr: felt*) {
    alloc_locals;

    // Load factorial_n and copy it to the output segment.
    local factorial_n;
    %{ ids.factorial_n = program_input['factorial_n'] %}

    assert output_ptr[0] = factorial_n;
    let res = factorial(factorial_n);
    assert output_ptr[1] = res;

    // Return the updated output_ptr.
    return (output_ptr=&output_ptr[2]);
}

func factorial(n: felt) -> felt {
    if (n == 0) {
        return 1;
    }
    if (n == 1) {
        return 1;
    }

    let n_minus_1 = factorial(n - 1);
    return n * n_minus_1;
}
