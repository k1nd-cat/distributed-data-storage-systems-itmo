create table if not exists s333304.table1
(
    id         serial primary key,
    title      varchar(50),
    number     integer,
    created_at date
);

create or replace function s333304.title_to_upper_case()
    returns trigger as
$$
begin
    new.title := upper(new.title);
    return new;
end;
$$ language plpgsql;

create or replace function s333304.negative_number_to_zero()
    returns trigger as
$$
begin
    if new.number < 0 then
        new.number := 0;
    end if;
    return new;
end;
$$ language plpgsql;

create or replace function s333304.set_created_at()
    returns trigger as
$$
begin
    new.created_at := current_date;
    return new;
end;
$$ language plpgsql;

create or replace trigger title_to_upper_case_trigger
    before insert or update of title
    on s333304.table1
    for each row
    when (new.title is not null and new.title <> '')
execute function s333304.title_to_upper_case();

create or replace trigger negative_number_to_zero_trigger
    before insert or update of number
    on s333304.table1
    for each row
    when (new.number is not null)
execute function s333304.negative_number_to_zero();

create or replace trigger set_created_at_trigger
    before insert
    on s333304.table1
    for each row
execute function s333304.set_created_at();

insert into s333304.table1 (title, number)
values ('test1', -1),
       ('Test2', 2),
       ('TEST3', -3);



create or replace function s333304.increase_positive_number()
    returns trigger as
$$
begin
    if new.number > 0 then
        new.number := new.number + 100;
    end if;
    return new;
end;
$$ language plpgsql;

create or replace trigger increase_positive_number_trigger
    before insert or update of number
    on s333304.table1
    for each row
    when (new.number is not null)
execute function s333304.increase_positive_number();