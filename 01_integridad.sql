/* =========================================================
   01_integridad.sql  -  Entregable E1 (Unidad I)
   Ejecutar DESPUÉS del script base 01_BusRD_base.sql.
   Orden: 1) detección  2) limpieza  3) restricciones  4) verificación
   ========================================================= */
USE BusRD;
GO
SET NOCOUNT ON;
GO

/* =========================================================
   1) DETECCIÓN DE DATOS SUCIOS
   ========================================================= */

-- 1.a Boletos activos duplicados (mismo viaje y mismo asiento)
SELECT ViajeID, NumeroAsiento, COUNT(*) AS BoletosActivos
FROM dbo.Boletos
WHERE Estado = 'Activo'
GROUP BY ViajeID, NumeroAsiento
HAVING COUNT(*) > 1;

-- 1.b Pagos huérfanos (apuntan a un boleto que no existe)
SELECT p.PagoID, p.BoletoID, p.Monto, p.Metodo, p.FechaPago
FROM dbo.Pagos p
LEFT JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL;

-- 1.c Boletos activos sin pago (no debería haber ninguno)
SELECT b.BoletoID, b.ViajeID, b.NumeroAsiento
FROM dbo.Boletos b
LEFT JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID
WHERE b.Estado = 'Activo' AND p.PagoID IS NULL;
GO

/* =========================================================
   2) LIMPIEZA CON REGLA JUSTIFICADA
   Regla de duplicados: en cada grupo (viaje, asiento) se conserva el boleto
   activo vendido primero (FechaVenta, luego BoletoID). Los demás se anulan
   y se registra un pago inverso (monto negativo) para dejar el cobro neteado
   a cero, igual que haría sp_AnularBoleto.
   Regla de pagos huérfanos: no tienen boleto que los justifique y no pueden
   sobrevivir a la FK, así que se copian al registro de limpieza y luego se eliminan.
   Todo lo queda documentado en dbo.Limpieza_Registro.
   ========================================================= */

-- Tabla de auditoría de la limpieza
IF OBJECT_ID('dbo.Limpieza_Registro') IS NULL
CREATE TABLE dbo.Limpieza_Registro (
    RegistroID     INT IDENTITY PRIMARY KEY,
    Tabla          VARCHAR(20)  NOT NULL,
    LlaveOriginal  VARCHAR(50)  NOT NULL,
    Accion         VARCHAR(30)  NOT NULL,
    Detalle        VARCHAR(200) NOT NULL,
    Fecha          DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO

SET XACT_ABORT ON;   -- cualquier error revierte toda la limpieza
BEGIN TRAN;

IF OBJECT_ID('tempdb..#Dup') IS NOT NULL DROP TABLE #Dup;

;WITH Ranked AS (
    SELECT BoletoID,
           ROW_NUMBER() OVER (PARTITION BY ViajeID, NumeroAsiento
                              ORDER BY FechaVenta, BoletoID) AS rn
    FROM dbo.Boletos
    WHERE Estado = 'Activo'
)
SELECT BoletoID INTO #Dup FROM Ranked WHERE rn > 1;

-- 2.a Registrar qué se va a anular
INSERT dbo.Limpieza_Registro (Tabla, LlaveOriginal, Accion, Detalle)
SELECT 'Boletos', CAST(BoletoID AS VARCHAR(50)), 'Anulado',
       'Asiento ya vendido en otro boleto activo; se anula el vendido más tarde'
FROM #Dup;

-- 2.b Anular los boletos duplicados
UPDATE b
SET b.Estado = 'Anulado'
FROM dbo.Boletos b
JOIN #Dup d ON d.BoletoID = b.BoletoID;

-- 2.c Registrar el reverso del pago y crearlo (monto negativo)
INSERT dbo.Limpieza_Registro (Tabla, LlaveOriginal, Accion, Detalle)
SELECT 'Pagos', CAST(p.PagoID AS VARCHAR(50)), 'Reverso',
       CONCAT('Pago de boleto duplicado neteado con monto ', -p.Monto)
FROM dbo.Pagos p
JOIN #Dup d ON d.BoletoID = p.BoletoID;

INSERT dbo.Pagos (BoletoID, Monto, Metodo, FechaPago)
SELECT p.BoletoID, -p.Monto, p.Metodo, SYSDATETIME()
FROM dbo.Pagos p
JOIN #Dup d ON d.BoletoID = p.BoletoID;

-- 2.d Registrar y eliminar los pagos huérfanos
INSERT dbo.Limpieza_Registro (Tabla, LlaveOriginal, Accion, Detalle)
SELECT 'Pagos', CAST(p.PagoID AS VARCHAR(50)), 'Eliminado',
       CONCAT('Pago sin boleto (BoletoID ', p.BoletoID, ', monto ', p.Monto, ')')
FROM dbo.Pagos p
LEFT JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL;

DELETE p
FROM dbo.Pagos p
LEFT JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL;

COMMIT TRAN;
SET XACT_ABORT OFF;
GO

/* =========================================================
   3) RESTRICCIONES
   ========================================================= */

-- 3.a Unicidad
ALTER TABLE dbo.Clientes  ADD CONSTRAINT UQ_Clientes_Cedula UNIQUE (Cedula);
ALTER TABLE dbo.Autobuses ADD CONSTRAINT UQ_Autobuses_Placa UNIQUE (Placa);

-- 3.b Dominio (valores permitidos)
ALTER TABLE dbo.Autobuses ADD CONSTRAINT CK_Autobuses_Tipo
    CHECK (Tipo IN ('Estandar', 'Ejecutivo'));
ALTER TABLE dbo.Asientos ADD CONSTRAINT CK_Asientos_Ubicacion
    CHECK (Ubicacion IN ('Ventana', 'Pasillo'));
ALTER TABLE dbo.Viajes ADD CONSTRAINT CK_Viajes_Estado
    CHECK (Estado IN ('Programado', 'Completado', 'Cancelado'));
ALTER TABLE dbo.Boletos ADD CONSTRAINT CK_Boletos_Estado
    CHECK (Estado IN ('Activo', 'Anulado'));
ALTER TABLE dbo.Boletos ADD CONSTRAINT CK_Boletos_Canal
    CHECK (Canal IN ('Taquilla', 'Web'));
ALTER TABLE dbo.Pagos ADD CONSTRAINT CK_Pagos_Metodo
    CHECK (Metodo IN ('Efectivo', 'Tarjeta', 'Transferencia'));

-- 3.c Rango
ALTER TABLE dbo.Rutas ADD CONSTRAINT CK_Rutas_Distancia CHECK (DistanciaKm > 0);
ALTER TABLE dbo.Rutas ADD CONSTRAINT CK_Rutas_Precio    CHECK (PrecioBase > 0);
ALTER TABLE dbo.Autobuses ADD CONSTRAINT CK_Autobuses_Capacidad
    CHECK (Capacidad BETWEEN 1 AND 100);
ALTER TABLE dbo.Asientos ADD CONSTRAINT CK_Asientos_Numero
    CHECK (NumeroAsiento > 0);
ALTER TABLE dbo.Boletos ADD CONSTRAINT CK_Boletos_Precio CHECK (Precio > 0);
-- Monto <> 0 en lugar de > 0: los reversos (anulaciones) son montos negativos
ALTER TABLE dbo.Pagos ADD CONSTRAINT CK_Pagos_Monto CHECK (Monto <> 0);

-- 3.d Llaves foráneas
ALTER TABLE dbo.Asientos ADD CONSTRAINT FK_Asientos_Autobuses
    FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses (AutobusID);
ALTER TABLE dbo.Viajes ADD CONSTRAINT FK_Viajes_Rutas
    FOREIGN KEY (RutaID) REFERENCES dbo.Rutas (RutaID);
ALTER TABLE dbo.Viajes ADD CONSTRAINT FK_Viajes_Autobuses
    FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses (AutobusID);
ALTER TABLE dbo.Boletos ADD CONSTRAINT FK_Boletos_Viajes
    FOREIGN KEY (ViajeID) REFERENCES dbo.Viajes (ViajeID);
ALTER TABLE dbo.Boletos ADD CONSTRAINT FK_Boletos_Clientes
    FOREIGN KEY (ClienteID) REFERENCES dbo.Clientes (ClienteID);
ALTER TABLE dbo.Pagos ADD CONSTRAINT FK_Pagos_Boletos
    FOREIGN KEY (BoletoID) REFERENCES dbo.Boletos (BoletoID);
GO

/* Boletos -> Asientos no se puede expresar como FK directa, porque Boletos
   no tiene AutobusID; el asiento depende del autobús del viaje. Se garantiza
   con un trigger que rechaza cualquier boleto cuyo asiento no exista en el
   autobús de su viaje. */
CREATE OR ALTER TRIGGER dbo.TR_Boletos_AsientoValido
ON dbo.Boletos
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.Viajes v
            JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
            WHERE v.ViajeID = i.ViajeID
              AND s.NumeroAsiento = i.NumeroAsiento))
    BEGIN
        THROW 50001, 'El asiento no existe en el autobús asignado al viaje.', 1;
    END
END
GO

/* Garantía de E1.4: no puede haber dos boletos activos para el mismo asiento
   del mismo viaje. Un boleto anulado queda fuera del índice y libera el asiento. */
CREATE UNIQUE NONCLUSTERED INDEX UX_Boletos_AsientoActivo
ON dbo.Boletos (ViajeID, NumeroAsiento)
WHERE Estado = 'Activo';
GO

/* =========================================================
   4) VERIFICACIÓN (todas deben dar 0 filas o los valores indicados)
   ========================================================= */
SELECT 'Duplicados activos' AS Control, COUNT(*) AS Resultado
FROM (SELECT ViajeID, NumeroAsiento FROM dbo.Boletos
      WHERE Estado = 'Activo'
      GROUP BY ViajeID, NumeroAsiento HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'Pagos huérfanos', COUNT(*)
FROM dbo.Pagos p LEFT JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL
UNION ALL
SELECT 'Registros de limpieza', COUNT(*) FROM dbo.Limpieza_Registro;
GO
