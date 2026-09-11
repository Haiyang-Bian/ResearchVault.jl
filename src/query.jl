const QUERY_OPERATORS = Set(("eq", "gt", "gte", "lt", "lte", "in", "between"))
const AGGREGATE_FUNCTIONS = Set(("count", "sum", "mean", "min", "max"))
const TIME_BUCKET_INTERVALS = Set(("hour", "day", "week", "month"))

struct QueryFilter
    column::String
    op::String
    value::Any
    values::Union{Nothing,Vector{Any}}

    function QueryFilter(column, op; value=nothing, values=nothing)
        normalized_op = String(op)
        normalized_op in QUERY_OPERATORS || throw(ArgumentError("unsupported query operator"))
        isempty(String(column)) && throw(ArgumentError("filter column cannot be empty"))
        normalized_values = values === nothing ? nothing : Any[_json_value(item) for item in values]
        if normalized_op in ("eq", "gt", "gte", "lt", "lte")
            value === nothing && throw(ArgumentError("$normalized_op requires value"))
        elseif normalized_op == "in"
            (normalized_values === nothing || isempty(normalized_values)) &&
                throw(ArgumentError("in requires values"))
            length(normalized_values) <= 100 || throw(ArgumentError("in supports at most 100 values"))
        elseif normalized_op == "between"
            normalized_values !== nothing && length(normalized_values) == 2 ||
                throw(ArgumentError("between requires exactly two values"))
        end
        return new(String(column), normalized_op, _json_value(value), normalized_values)
    end
end

struct QueryAggregate
    function_name::String
    column::Union{Nothing,String}
    alias::Union{Nothing,String}

    function QueryAggregate(function_name; column=nothing, alias=nothing)
        normalized = String(function_name)
        normalized in AGGREGATE_FUNCTIONS ||
            throw(ArgumentError("unsupported aggregate function"))
        normalized != "count" && column === nothing &&
            throw(ArgumentError("$normalized requires a column"))
        return new(normalized, column === nothing ? nothing : String(column), alias === nothing ? nothing : String(alias))
    end
end

struct QueryTimeBucket
    column::String
    interval::String
    alias::Union{Nothing,String}

    function QueryTimeBucket(column, interval; alias=nothing)
        normalized = String(interval)
        normalized in TIME_BUCKET_INTERVALS || throw(ArgumentError("unsupported time bucket"))
        return new(String(column), normalized, alias === nothing ? nothing : String(alias))
    end
end

struct QueryOrder
    column::String
    direction::String

    function QueryOrder(column; direction="asc")
        normalized = String(direction)
        normalized in ("asc", "desc") || throw(ArgumentError("order direction must be asc or desc"))
        return new(String(column), normalized)
    end
end

struct QuerySpec
    columns::Vector{String}
    filters::Vector{QueryFilter}
    aggregates::Vector{QueryAggregate}
    group_by::Vector{String}
    time_bucket::Union{Nothing,QueryTimeBucket}
    order_by::Vector{QueryOrder}
    limit::Int

    function QuerySpec(
        ;
        columns=String[],
        filters=QueryFilter[],
        aggregates=QueryAggregate[],
        group_by=String[],
        time_bucket=nothing,
        order_by=QueryOrder[],
        limit::Integer=4_000,
    )
        1 <= limit <= 4_000 || throw(ArgumentError("query limit must be between 1 and 4000"))
        length(columns) <= 64 || throw(ArgumentError("query supports at most 64 columns"))
        length(filters) <= 32 || throw(ArgumentError("query supports at most 32 filters"))
        length(aggregates) <= 32 || throw(ArgumentError("query supports at most 32 aggregates"))
        length(group_by) <= 16 || throw(ArgumentError("query supports at most 16 group columns"))
        length(order_by) <= 8 || throw(ArgumentError("query supports at most 8 order clauses"))
        return new(
            String.(columns),
            QueryFilter[filters...],
            QueryAggregate[aggregates...],
            String.(group_by),
            time_bucket,
            QueryOrder[order_by...],
            Int(limit),
        )
    end
end

function _wire(filter::QueryFilter)
    return Dict(
        "column" => filter.column,
        "op" => filter.op,
        "value" => filter.value,
        "values" => filter.values,
    )
end

function _wire(aggregate::QueryAggregate)
    return Dict(
        "function" => aggregate.function_name,
        "column" => aggregate.column,
        "alias" => aggregate.alias,
    )
end

function _wire(bucket::QueryTimeBucket)
    return Dict("column" => bucket.column, "interval" => bucket.interval, "alias" => bucket.alias)
end

_wire(order::QueryOrder) = Dict("column" => order.column, "direction" => order.direction)

function _wire(query::QuerySpec)
    return Dict(
        "columns" => query.columns,
        "filters" => _wire.(query.filters),
        "aggregates" => _wire.(query.aggregates),
        "group_by" => query.group_by,
        "time_bucket" => query.time_bucket === nothing ? nothing : _wire(query.time_bucket),
        "order_by" => _wire.(query.order_by),
        "limit" => query.limit,
    )
end

struct VaultTable
    columns::Vector{String}
    rows::Vector{NamedTuple}
    column_types::Vector{Type}
    metadata::JsonObject
end

Tables.istable(::Type{VaultTable}) = true
Tables.rowaccess(::Type{VaultTable}) = true
Tables.rows(table::VaultTable) = table.rows
Tables.columnnames(table::VaultTable) = Tuple(Symbol.(table.columns))
Tables.schema(table::VaultTable) =
    Tables.Schema(Tuple(Symbol.(table.columns)), Tuple(table.column_types))
Base.length(table::VaultTable) = length(table.rows)
Base.getindex(table::VaultTable, index::Integer) = table.rows[index]
Base.iterate(table::VaultTable, state...) = iterate(table.rows, state...)

function _vault_table(value)
    o = _strict_object(value, ("logical_path", "columns", "row_count", "rows"))
    columns = _strings(o["columns"], "columns")
    length(unique(columns)) == length(columns) || _invalid_response("query columns are duplicated")
    raw_rows = _vector(o["rows"], "rows")
    _integer(o["row_count"], "row_count") == length(raw_rows) ||
        _invalid_response("query row_count does not match rows")
    names = Tuple(Symbol.(columns))
    rows = NamedTuple[]
    for raw_row in raw_rows
        row = _object(raw_row, "row")
        Set(keys(row)) == Set(columns) || _invalid_response("query row columns do not match schema")
        values = Tuple(isnothing(row[column]) ? missing : row[column] for column in columns)
        push!(rows, NamedTuple{names}(values))
    end
    column_types = Type[]
    for name in names
        values = [getproperty(row, name) for row in rows]
        present = filter(!ismissing, values)
        value_type = isempty(present) ? Any : reduce(typejoin, typeof.(present))
        any(ismissing, values) && value_type !== Any && (value_type = Union{Missing,value_type})
        push!(column_types, value_type)
    end
    metadata = Dict{String,Any}(
        "logical_path" => o["logical_path"],
        "row_count" => o["row_count"],
    )
    return VaultTable(columns, rows, column_types, metadata)
end

function _run_window_table(value, variables::Vector{String})
    o = _strict_object(value, ("timestamps", "scenario_indices", "scenarios"))
    timestamps = _strings(o["timestamps"], "timestamps")
    indices = [_integer(item, "scenario_indices") for item in _vector(o["scenario_indices"], "scenario_indices")]
    scenarios = _vector(o["scenarios"], "scenarios")
    length(indices) == length(scenarios) || _invalid_response("scenario_indices do not match scenarios")
    columns = ["timestamp", "scenario_index", variables...]
    names = Tuple(Symbol.(columns))
    rows = NamedTuple[]
    for (scenario_position, raw_scenario) in enumerate(scenarios)
        scenario = _object(raw_scenario, "scenario")
        Set(keys(scenario)) == Set(variables) || _invalid_response("run query variables do not match request")
        for variable in variables
            values = _vector(scenario[variable], variable)
            length(values) == length(timestamps) || _invalid_response("run query series length mismatch")
        end
        for time_index in eachindex(timestamps)
            values = Any[timestamps[time_index], indices[scenario_position]]
            append!(values, [scenario[variable][time_index] for variable in variables])
            push!(rows, NamedTuple{names}(Tuple(values)))
        end
    end
    column_types = Type[String, Int]
    append!(column_types, fill(Real, length(variables)))
    metadata = Dict{String,Any}(
        "scenario_indices" => indices,
        "retained_point_count" => length(timestamps),
    )
    return VaultTable(columns, rows, column_types, metadata)
end
