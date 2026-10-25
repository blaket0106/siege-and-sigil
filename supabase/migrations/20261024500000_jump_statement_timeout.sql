alter function public.admin_jump_ticks(int, int) set statement_timeout = '60s';
alter function public.process_ticks(int) set statement_timeout = '60s';
