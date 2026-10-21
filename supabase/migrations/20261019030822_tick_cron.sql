create extension if not exists pg_cron;

select cron.schedule(
  'process-due-games',
  '* * * * *',
  $job$select public.process_due_games()$job$
);
