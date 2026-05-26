using Microsoft.Data.SqlClient;

namespace KhulisaQuery.Api.Services;

public interface IDbConnectionFactory
{
    Task<SqlConnection> OpenAsync(CancellationToken ct = default);
}

public class SqlConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;

    public SqlConnectionFactory(string connectionString)
        => _connectionString = connectionString;

    public async Task<SqlConnection> OpenAsync(CancellationToken ct = default)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }
}
