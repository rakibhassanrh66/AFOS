-- students.batch_id was null for every row because the `batches` table
-- itself was never populated -- students.batch_label (free text, the field
-- actually used everywhere else in the app) already carries the real value,
-- this just gives the structured FK something to point at for the 3 real
-- student rows that have both program_id and batch_label set. Rows with
-- neither (QA seed accounts) are left alone -- there's nothing to derive.
insert into batches (program_id, name)
select distinct s.program_id, s.batch_label
from students s
where s.program_id is not null and s.batch_label is not null
  and not exists (
    select 1 from batches b where b.program_id = s.program_id and b.name = s.batch_label
  );

update students s
set batch_id = b.id
from batches b
where b.program_id = s.program_id and b.name = s.batch_label
  and s.batch_id is null and s.program_id is not null and s.batch_label is not null;
