-- The Flutter checkout flow (manage_library_screen.dart) previously read
-- books.available_copies client-side then wrote back current-1/current+1 —
-- a classic read-then-write race: two staff issuing the last copy of the
-- same book at the same time could both read available_copies=1, both
-- decrement to 0, and both succeed, oversubscribing the book. Moving the
-- arithmetic into a trigger makes it atomic (Postgres row-locks the books
-- row for the duration of the UPDATE), and lets the DB itself refuse to
-- issue a book with zero copies left even under concurrent requests.
create or replace function public.adjust_book_availability()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if TG_OP = 'INSERT' and new.status = 'borrowed' then
    update books set available_copies = available_copies - 1
    where id = new.book_id and available_copies > 0;
    if not found then
      raise exception 'No available copies of this book left';
    end if;
  elsif TG_OP = 'UPDATE' and old.status = 'borrowed' and new.status = 'returned' then
    update books set available_copies = available_copies + 1
    where id = new.book_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_adjust_book_availability on borrowed_books;
create trigger trg_adjust_book_availability
after insert or update on borrowed_books
for each row execute function public.adjust_book_availability();
