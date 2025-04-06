-- Создаем временную таблицу
create temp table if not exists temp_trigger_vars (
    id serial primary key,
    schema_name text not null,
    table_name text not null
);

-- Очищаем предыдущие значения
truncate table temp_trigger_vars;

-- Вставляем данные (предполагается, что переменные :'schema_name' и :'table_name' заданы)
insert into temp_trigger_vars (schema_name, table_name)
values (:'schema_name', :'table_name');

-- Основной анонимный блок
do $$
declare
    schema_name text;  -- Схема (значение будет из временной таблицы)
    table_name text;   -- Таблица (значение будет из временной таблицы)
    trig_record record;
    when_condition text;
    column_name text;
    output_text text := '';
    has_columns boolean;
begin
    -- Получаем schema_name и table_name из временной таблицы
    select 
        tv.schema_name, 
        tv.table_name 
    into 
        schema_name, 
        table_name 
    from temp_trigger_vars tv 
    limit 1;

    -- Проверка на NULL
    if schema_name is null or table_name is null then
        raise exception 'Данные схемы или таблицы не найдены во временной таблице';
    end if;

    -- Заголовки
    output_text := output_text ||
        'COLUMN NAME            TRIGGER NAME' || E'\n' ||
        '----------------------- ------------------------' || E'\n';

    -- Получаем триггеры таблицы
    for trig_record in
        select
            t.tgname as trigger_name,
            pg_get_triggerdef(t.oid) as trigger_def
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        where
            n.nspname = schema_name
            and c.relname = table_name
            and not t.tgisinternal
    loop
        when_condition := substring(trig_record.trigger_def from 'WHEN\s*\((.*?)\)');
        has_columns := false;

        -- Обработка WHEN
        if when_condition is not null then
            for column_name in
                select distinct m[2]
                from regexp_matches(when_condition, '(OLD|NEW)\.(\w+)', 'g') as m
            loop
                output_text := output_text ||
                    format('%-20s               %-20s', column_name, trig_record.trigger_name) || E'\n';
                has_columns := true;
            end loop;

            -- Если столбцы не найдены
            if not has_columns then
                output_text := output_text ||
                    format('%-20s           %-20s', 'NULL', trig_record.trigger_name) || E'\n';
            end if;
        else
            -- Триггеры без WHEN
            output_text := output_text ||
                format('%-20s           %-20s', 'NULL', trig_record.trigger_name) || E'\n';
        end if;
    end loop;

    -- Убираем последний перевод строки
    output_text := trim(trailing E'\n' from output_text);

    -- Вывод результата
    raise notice E'\n%s', output_text;

exception
    when others then
        raise notice 'Ошибка: %', sqlerrm;
        raise notice 'Проверьте:';
        raise notice '- Корректность schema_name и table_name во временной таблице';
        raise notice '- Существование таблицы в указанной схеме';
end;
$$ language plpgsql;