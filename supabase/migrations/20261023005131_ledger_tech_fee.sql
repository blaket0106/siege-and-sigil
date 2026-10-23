alter table public.ledger drop constraint ledger_type_check;
alter table public.ledger add constraint ledger_type_check check (type = any (array['starting_gold', 'production', 'send_gold', 'receive_gold', 'recruit', 'upgrade', 'road', 'capture', 'salvage', 'tech_fee']));
