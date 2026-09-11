# Source migration

`ResearchVault.jl` was developed in the private Research Vault product monorepo and is being
published as a clean, self-contained package repository. The public import preserves package UUID
`7a53f6f4-db81-43fb-8cd3-ce159c3c5249` and version `0.5.1`, but intentionally does not reproduce
the private product repository history.

The import baseline is Research Vault merge commit
`d1382fcdd421c3b375e5629231e5adde8f334395` plus the self-containment changes recorded in the
product repository's 0.14.0 modular-build branch. A generated file manifest and its SHA-256 are
recorded in the first public release notes so the imported source can be audited without exposing
unrelated private history.

The implementation and documentation were developed with substantial AI assistance. A human
maintainer must review and understand the public source, tests, license, and API before requesting
General Registry registration. This statement is provenance disclosure, not a substitute for that
review.
