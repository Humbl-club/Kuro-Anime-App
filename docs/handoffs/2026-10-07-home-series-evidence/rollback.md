# Rollback — prepared series/Home migration

This migration is not deployed. Rollback of the file before any apply is: do not run it.

After an authorized apply, disable the client flags first (`series_home_native_v1`, `series_foundation_v1`). The old pager and the old detail views remain in the binary. Do not drop `mutation_receipts` or list rows to roll back. Pending SQLite intents live in Application Support `Kuro/progress-outbox.sqlite` and must be kept; turning the flag off does not delete them and does not replay them through a full-row upsert.

A later schema rollback, only with explicit approval and a backup, can drop the new tables and the added list columns. That destroys receipts and precise labels. It is not the default rollback.
