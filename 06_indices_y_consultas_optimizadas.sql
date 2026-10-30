/* =========================================================
   06_indices_y_consultas_optimizadas.sql  -  Entregable E3 (Unidad II)
   Para C1, C2 y C3: línea base, índices, consultas reescritas
   y comprobación de que devuelven el mismo resultado.
   Capturar el plan real con Ctrl+M (Include Actual Execution Plan).
   Los valores marcados CAMBIAR deben ser los del grupo.
   ========================================================= */
USE BusRD;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* ===== 1. LÍNEA BASE (consultas originales) =====
   Nota: el índice UX_Boletos_AsientoActivo ya existe por E1, así que la
   línea base ya lo incluye. Para medir sin índices, eliminarlo en una copia. */

-- C1 ANTES
DECLARE @ViajeID INT = 16000;  -- CAMBIAR: viaje asignado al grupo
SELECT s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND s.NumeroAsiento NOT IN (SELECT b.NumeroAsiento
                              FROM dbo.Boletos b
                              WHERE b.ViajeID = @ViajeID
                                AND b.Estado = 'Activo')
ORDER BY s.NumeroAsiento;
GO

-- C2 ANTES
DECLARE @Cedula CHAR(11) = '40200012345';  -- CAMBIAR: cédula del cliente N° grupo × 1000
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula
ORDER BY v.FechaSalida DESC;
GO

-- C3 ANTES
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE YEAR(b.FechaVenta) = 2025
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta)
ORDER BY r.Origen, r.Destino, Mes;
GO

/* ===== 2. ÍNDICES =====
   C1: no necesita índice nuevo. El filtro (ViajeID, NumeroAsiento) WHERE
       Estado = 'Activo' ya lo cubre UX_Boletos_AsientoActivo (E1).
   C2: la búsqueda por cédula usa el índice único de Clientes.Cedula (E1).
       Falta el acceso a Boletos por ClienteID: se crea IX_Boletos_ClienteID
       con INCLUDE para no tener que ir a la tabla base.
   C3: el filtro por fecha necesita un índice en FechaVenta; INCLUDE evita
       búsquedas adicionales. El join con Pagos necesita un índice en BoletoID. */
CREATE NONCLUSTERED INDEX IX_Boletos_ClienteID
ON dbo.Boletos (ClienteID)
INCLUDE (ViajeID, NumeroAsiento, Precio, Estado);

CREATE NONCLUSTERED INDEX IX_Boletos_FechaVenta
ON dbo.Boletos (FechaVenta)
INCLUDE (BoletoID, ViajeID, Estado);

CREATE NONCLUSTERED INDEX IX_Pagos_BoletoID
ON dbo.Pagos (BoletoID)
INCLUDE (Monto);
GO

/* ===== 3. CONSULTAS REESCRITAS (sargables) ===== */

-- C1 DESPUÉS: NOT EXISTS en lugar de NOT IN (mismo resultado, porque NumeroAsiento no admite NULL)
DECLARE @ViajeID INT = 16000;  -- CAMBIAR
SELECT s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND NOT EXISTS (SELECT 1
                  FROM dbo.Boletos b
                  WHERE b.ViajeID = @ViajeID
                    AND b.NumeroAsiento = s.NumeroAsiento
                    AND b.Estado = 'Activo')
ORDER BY s.NumeroAsiento;
GO

-- C2 DESPUÉS: sin LTRIM/RTRIM sobre la columna (CHAR(11) ya tiene 11 caracteres exactos)
DECLARE @Cedula CHAR(11) = '40200012345';  -- CAMBIAR
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE c.Cedula = @Cedula
ORDER BY v.FechaSalida DESC;
GO

-- C3 DESPUÉS: rango de fechas en lugar de YEAR() sobre la columna
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.FechaVenta >= '2025-01-01'
  AND b.FechaVenta <  '2026-01-01'
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta)
ORDER BY r.Origen, r.Destino, Mes;
GO

/* ===== 4. COMPROBACIÓN: original y reescrita devuelven lo mismo =====
   Diferencias = 0 significa que no hay filas que estén solo en una de las dos. */
DECLARE @ViajeID INT = 16000, @Cedula CHAR(11) = '40200012345';  -- CAMBIAR

SELECT s.NumeroAsiento, s.Ubicacion INTO #C1_orig
FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND s.NumeroAsiento NOT IN (SELECT b.NumeroAsiento FROM dbo.Boletos b
                              WHERE b.ViajeID = @ViajeID AND b.Estado = 'Activo');

SELECT s.NumeroAsiento, s.Ubicacion INTO #C1_new
FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                  WHERE b.ViajeID = @ViajeID AND b.NumeroAsiento = s.NumeroAsiento AND b.Estado = 'Activo');

SELECT c.Nombre, c.Apellido, r.Origen, r.Destino, v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado INTO #C2_orig
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID
JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula;

SELECT c.Nombre, c.Apellido, r.Origen, r.Destino, v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado INTO #C2_new
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID
JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE c.Cedula = @Cedula;

SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes, COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos INTO #C3_orig
FROM dbo.Boletos b
JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID
JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE YEAR(b.FechaVenta) = 2025 AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);

SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes, COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos INTO #C3_new
FROM dbo.Boletos b
JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID
JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE b.FechaVenta >= '2025-01-01' AND b.FechaVenta < '2026-01-01' AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);

SELECT 'C1' AS Consulta,
       (SELECT COUNT(*) FROM (SELECT * FROM #C1_orig EXCEPT SELECT * FROM #C1_new) a)
     + (SELECT COUNT(*) FROM (SELECT * FROM #C1_new EXCEPT SELECT * FROM #C1_orig) b) AS Diferencias,
       (SELECT COUNT(*) FROM #C1_new) AS Filas
UNION ALL
SELECT 'C2',
       (SELECT COUNT(*) FROM (SELECT * FROM #C2_orig EXCEPT SELECT * FROM #C2_new) a)
     + (SELECT COUNT(*) FROM (SELECT * FROM #C2_new EXCEPT SELECT * FROM #C2_orig) b),
       (SELECT COUNT(*) FROM #C2_new)
UNION ALL
SELECT 'C3',
       (SELECT COUNT(*) FROM (SELECT * FROM #C3_orig EXCEPT SELECT * FROM #C3_new) a)
     + (SELECT COUNT(*) FROM (SELECT * FROM #C3_new EXCEPT SELECT * FROM #C3_orig) b),
       (SELECT COUNT(*) FROM #C3_new);

DROP TABLE #C1_orig, #C1_new, #C2_orig, #C2_new, #C3_orig, #C3_new;
GO

/* ===== 5. TABLA COMPARATIVA (completar con los valores de STATISTICS IO/TIME y los planes)
   Consulta | Lecturas lógicas antes | después | CPU ms antes | después | Operador costoso antes | después | Índice usado
   C1       |                        |         |              |         |                        |         |
   C2       |                        |         |              |         |                        |         |
   C3       |                        |         |              |         |                        |         |
*/

/* ===== 6. CONCLUSIÓN SOBRE sp_VenderBoleto =====
   Cada índice nuevo acelera las lecturas, pero cada INSERT en Boletos debe actualizar
   también IX_Boletos_ClienteID, IX_Boletos_FechaVenta y UX_Boletos_AsientoActivo.
   Medir el tiempo de la venta con y sin estos índices y comentarlo en el informe. */
