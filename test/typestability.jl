@testitem "JET - Package" begin
    using JET
    if JET.JET_AVAILABLE
        test_package(Mermaid; target_modules=(Mermaid,))
    end
end
