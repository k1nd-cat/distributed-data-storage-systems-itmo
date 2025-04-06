create temp table if not exists temp_trigger_vars (
    id serial primary key,
    schema_name text not null,
    table_name text not null
);

truncate table temp_trigger_vars;

insert into temp_trigger_vars (schema_name, table_name)
values (:'schema_name', :'table_name');

do $$
declare
    schema_name text;
    table_name text;
    trig_record record;
    when_condition text;
    column_name text;
    output_text text := '';
    has_columns boolean;
begin
    select 
        tv.schema_name, 
        tv.table_name 
    into 
        schema_name, 
        table_name 
    from temp_trigger_vars tv 
    limit 1;

    if schema_name is null or table_name is null then
        raise exception 'Данные схемы или таблицы не найдены во временной таблице';
    end if;

    output_text := output_text ||
        'COLUMN NAME            TRIGGER NAME' || E'\n' ||
        '----------------------- ------------------------' || E'\n';

    for trig_record in
        select
            t.tgname as trigger_name,
            pg_get_triggerdef(t.oid) as trigger_def,
            array_agg(a.attname) as target_columns
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        left join pg_attribute a 
            on a.attrelid = t.tgrelid 
            and a.attnum = any(t.tgattr)
        where
            n.nspname = schema_name
            and c.relname = table_name
            and not t.tgisinternal
        group by t.tgname, t.oid, t.tgattr
    loop
        when_condition := substring(trig_record.trigger_def from 'WHEN\s*\((.*?)\)');
        has_columns := false;

        -- Колонки из UPDATE OF
        if trig_record.target_columns is not null then
            foreach column_name in array trig_record.target_columns loop
                output_text := output_text ||
                    format('%-20s               %-20s', column_name, trig_record.trigger_name) || E'\n';
                has_columns := true;
            end loop;
        end if;

        -- Колонки из WHEN
        if when_condition is not null then
            for column_name in
                select distinct m[2]
                from regexp_matches(when_condition, '(OLD|NEW)\.(\w+)', 'g') as m
            loop
                output_text := output_text ||
                    format('%-20s               %-20s', column_name, trig_record.trigger_name) || E'\n';
                has_columns := true;
            end loop;
        end if;

        -- Если колонок нет
        if not has_columns then
            output_text := output_text ||
                format('%-20s           %-20s', 'NULL', trig_record.trigger_name) || E'\n';
        end if;
    end loop;

    output_text := trim(trailing E'\n' from output_text);
    raise notice E'\n%s', output_text;

exception
    when others then
        raise notice 'Ошибка: %', sqlerrm;
        raise notice 'Проверьте:';
        raise notice '- Корректность schema_name и table_name во временной таблице';
        raise notice '- Существование таблицы в указанной схеме';
end;
$$ language plpgsql;