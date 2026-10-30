/* =========================================================
   07_seguridad.sql  -  Entregable E4 (Unidad III)
   Usuarios sin login, roles con mínimo privilegio, vistas y pruebas
   de acceso permitido y denegado con EXECUTE AS USER / REVERT.
   ========================================================= */
USE BusRD;
GO

/* ---------- 1) Usuarios sin login ---------- */
IF DATABASE_PRINCIPAL_ID('usr_taquilla') IS NULL CREATE USER usr_taquilla WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('usr_reportes') IS NULL CREATE USER usr_reportes WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('usr_admin')    IS NULL CREATE USER usr_admin    WITHOUT LOGIN;
GO

/* ---------- 2) Roles y asignación ---------- */
IF DATABASE_PRINCIPAL_ID('rol_taquilla') IS NULL CREATE ROLE rol_taquilla;
IF DATABASE_PRINCIPAL_ID('rol_reportes') IS NULL CREATE ROLE rol_reportes;
IF DATABASE_PRINCIPAL_ID('rol_admin')    IS NULL CREATE ROLE rol_admin;
GO
IF IS_ROLEMEMBER('rol_taquilla', 'usr_taquilla') IS NULL OR IS_ROLEMEMBER('rol_taquilla', 'usr_taquilla') = 0
    ALTER ROLE rol_taquilla ADD MEMBER usr_taquilla;
IF IS_ROLEMEMBER('rol_reportes', 'usr_reportes') IS NULL OR IS_ROLEMEMBER('rol_reportes', 'usr_reportes') = 0
    ALTER ROLE rol_reportes ADD MEMBER usr_reportes;
IF IS_ROLEMEMBER('rol_admin', 'usr_admin') IS NULL OR IS_ROLEMEMBER('rol_admin', 'usr_admin') = 0
    ALTER ROLE rol_admin ADD MEMBER usr_admin;
GO

/* ---------- 3) Vistas ---------- */
CREATE OR ALTER VIEW dbo.vw_AsientosDisponibles
AS
SELECT v.ViajeID, s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.Estado = 'Programado'
  AND NOT EXISTS (SELECT 1
                  FROM dbo.Boletos b
                  WHERE b.ViajeID = v.ViajeID
                    AND b.NumeroAsiento = s.NumeroAsiento
                    AND b.Estado = 'Activo');
GO
CREATE OR ALTER VIEW dbo.vw_VentasMensuales
AS
SELECT r.Origen, r.Destino,
       YEAR(b.FechaVenta)  AS Anio,
       MONTH(b.FechaVenta) AS Mes,
       COUNT(*)            AS Boletos,
       SUM(p.Monto)        AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, YEAR(b.FechaVenta), MONTH(b.FechaVenta);
GO

/* ---------- 4) Permisos ---------- */
-- Taquilla: solo procedimientos y una vista. Sin acceso directo a tablas.
-- Funciona por ownership chaining: procedimientos, vistas y tablas tienen el mismo dueño (dbo).
GRANT EXECUTE ON dbo.sp_VenderBoleto TO rol_taquilla;
GRANT EXECUTE ON dbo.sp_AnularBoleto TO rol_taquilla;
GRANT SELECT  ON dbo.vw_AsientosDisponibles TO rol_taquilla;

-- Reportes: solo la vista de ventas. Sin acceso a Clientes (Email y Telefono explícitamente denegados).
GRANT SELECT ON dbo.vw_VentasMensuales TO rol_reportes;
DENY SELECT ON dbo.Clientes (Email, Telefono) TO rol_reportes;

-- Admin: administración completa.
IF IS_ROLEMEMBER('db_owner', 'rol_admin') = 0
    ALTER ROLE db_owner ADD MEMBER rol_admin;
GO

/* ---------- 5) Pruebas: permitido y denegado ---------- */
DECLARE @ViajeID INT = 16000;  -- CAMBIAR: viaje asignado (Programado)

/* --- Taquilla --- */
EXECUTE AS USER = 'usr_taquilla';
-- PERMITIDO 1: consultar la vista de asientos disponibles
SELECT TOP (5) ViajeID, NumeroAsiento, Ubicacion
FROM dbo.vw_AsientosDisponibles WHERE ViajeID = @ViajeID ORDER BY NumeroAsiento;

-- PERMITIDO 2: vender mediante el procedimiento (sin permiso sobre Boletos)
BEGIN TRY
    DECLARE @Asiento INT = (SELECT TOP (1) NumeroAsiento FROM dbo.vw_AsientosDisponibles
                            WHERE ViajeID = @ViajeID ORDER BY NumeroAsiento);
    DECLARE @Boleto INT;
    EXEC dbo.sp_VenderBoleto @ViajeID = @ViajeID, @NumeroAsiento = @Asiento,
         @ClienteID = 1001, @Canal = 'Taquilla', @Metodo = 'Efectivo', @BoletoID = @Boleto OUTPUT;
    SELECT 'PERMITIDO: venta con sp_VenderBoleto' AS Prueba, @Boleto AS BoletoID;
END TRY
BEGIN CATCH
    SELECT 'Venta no ejecutada' AS Prueba, ERROR_MESSAGE() AS Mensaje;
END CATCH

-- DENEGADO 1: lectura directa de la tabla
BEGIN TRY
    SELECT TOP (5) * FROM dbo.Boletos;
END TRY
BEGIN CATCH
    SELECT 'DENEGADO: SELECT sobre Boletos' AS Prueba, ERROR_NUMBER() AS Error, ERROR_MESSAGE() AS Mensaje;
END CATCH

-- DENEGADO 2: modificación directa de la tabla
BEGIN TRY
    UPDATE dbo.Boletos SET Estado = 'Anulado' WHERE BoletoID = 1;
END TRY
BEGIN CATCH
    SELECT 'DENEGADO: UPDATE sobre Boletos' AS Prueba, ERROR_NUMBER() AS Error, ERROR_MESSAGE() AS Mensaje;
END CATCH
REVERT;
GO

/* --- Reportes --- */
DECLARE @ViajeID INT = 16000;
EXECUTE AS USER = 'usr_reportes';
-- PERMITIDO 1
SELECT TOP (5) * FROM dbo.vw_VentasMensuales ORDER BY Anio DESC, Mes DESC;

-- DENEGADO 1: correo de clientes
BEGIN TRY
    SELECT TOP (5) Email FROM dbo.Clientes;
END TRY
BEGIN CATCH
    SELECT 'DENEGADO: SELECT Email' AS Prueba, ERROR_NUMBER() AS Error, ERROR_MESSAGE() AS Mensaje;
END CATCH

-- DENEGADO 2: tabla de boletos
BEGIN TRY
    SELECT TOP (5) * FROM dbo.Boletos;
END TRY
BEGIN CATCH
    SELECT 'DENEGADO: SELECT sobre Boletos' AS Prueba, ERROR_NUMBER() AS Error, ERROR_MESSAGE() AS Mensaje;
END CATCH
REVERT;
GO

/* --- Admin --- */
EXECUTE AS USER = 'usr_admin';
-- PERMITIDO 1 y 2
SELECT COUNT(*) AS BoletosTotales FROM dbo.Boletos;
SELECT COUNT(*) AS ClientesTotales FROM dbo.Clientes;
REVERT;
GO

/* ---------- 6) Explicación para el informe ----------
   Mínimo privilegio: cada rol recibe solo lo que su trabajo necesita.
   Ownership chaining: cuando un procedimiento y las tablas que usa tienen el mismo dueño,
   SQL Server no revisa permisos sobre las tablas al ejecutar el procedimiento.
   Por eso taquilla puede vender sin tener SELECT, INSERT ni UPDATE sobre Boletos o Pagos. */
