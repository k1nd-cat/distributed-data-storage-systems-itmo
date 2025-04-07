-- Создание временной таблицы
create temp table if not exists temp_trigger_vars (
    id serial primary key,
    full_table_name text not null
);

-- Очистка временной таблицы
truncate table temp_trigger_vars;

-- Вставка имени таблицы (возможно: table, schema.table, database.schema.table)
insert into temp_trigger_vars (full_table_name)
values (:'table_name');

do $$
declare
    full_table_name text;
    schema_name text;
    table_name text;
    parts text[];
    db_part text;
    trig_record record;
    when_condition text;
    column_name text;
    output_text text := '';
    has_columns boolean;
    table_oid oid;
    search_path_arr text[];
begin
    -- Получаем полное имя таблицы
    select tv.full_table_name into full_table_name from temp_trigger_vars tv limit 1;

    if full_table_name is null then
        raise exception 'Имя таблицы не указано';
    end if;

    -- Разбиваем имя таблицы на части
    parts := parse_ident(full_table_name);

    -- Проверка количества частей
    if array_length(parts, 1) < 1 or array_length(parts, 1) > 3 then
        raise exception 'Недопустимый формат имени таблицы. Используйте: database.schema.table, schema.table или table';
    end if;

    -- Разбор частей
    case array_length(parts, 1)
        when 3 then
            db_part := parts[1];
            schema_name := parts[2];
            table_name := parts[3];
            if db_part != current_database() then
                raise exception 'Указанная база данных "%" не совпадает с текущей "%"', db_part, current_database();
            end if;
        when 2 then
            schema_name := parts[1];
            table_name := parts[2];
        when 1 then
            schema_name := null;
            table_name := parts[1];
    end case;

    -- Получаем OID таблицы
    table_oid := to_regclass(
        case 
            when schema_name is not null then format('%I.%I', schema_name, table_name)
            else format('%I', table_name)
        end
    );

    if table_oid is null then
        show search_path into search_path_arr;
        if schema_name is not null then
            raise exception 'Таблица "%" не найдена в схеме "%"', table_name, schema_name;
        else
            raise exception 'Таблица "%" не найдена в search_path: %', table_name, search_path_arr;
        end if;
    end if;

    -- Если схема не указана, определяем её
    if schema_name is null then
        select n.nspname into schema_name
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where c.oid = table_oid;
    end if;

    -- Заголовок вывода
    output_text := output_text ||
        'COLUMN NAME            TRIGGER NAME' || E'\n' ||
        '----------------------- ------------------------' || E'\n';

    -- Цикл по триггерам
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

        -- Колонки из выражений WHEN
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

        -- Если не найдено ни одной колонки
        if not has_columns then
            output_text := output_text ||
                format('%-20s           %-20s', 'NULL', trig_record.trigger_name) || E'\n';
        end if;
    end loop;

    -- Вывод результата
    output_text := trim(trailing E'\n' from output_text);
    raise notice E'\n%s', output_text;

exception
    when others then
        raise notice 'Ошибка: %', sqlerrm;
        raise notice 'Проверьте:';
        raise notice '- Корректность формата имени таблицы (database.schema.table, schema.table, table)';
        raise notice '- Существование таблицы в указанной схеме или search_path';
        raise notice '- Соответствие базы данных (если указана) текущей БД';
end;
$$ language plpgsql;
