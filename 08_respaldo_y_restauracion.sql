/* =========================================================
   08_respaldo_y_restauracion.sql  -  Entregable E5 (Unidad III)
   Recuperación FULL, secuencia FULL -> DIFERENCIAL -> LOG -> error -> LOG de cola,
   restauración en BusRD_Recuperada hasta un momento antes del DELETE (STOPAT).
   Requisito: carpeta C:\Backups\BusRD\ creada.
   ========================================================= */

/* ---------- 1) Modelo de recuperación FULL ----------
   Justificación: con SIMPLE no existen respaldos de log, y sin ellos no se puede
   restaurar a un momento exacto (STOPAT). FULL registra todas las operaciones. */
USE master;
GO
ALTER DATABASE BusRD SET RECOVERY FULL;
GO
USE BusRD;
GO

/* ---------- 2) Respaldo FULL ---------- */
BACKUP DATABASE BusRD
TO DISK = 'C:\Backups\BusRD\BusRD_FULL.bak'
WITH INIT, NAME = 'BusRD FULL', CHECKSUM, STATS = 10;
GO

/* ---------- 3) Vender 5 boletos ----------
   Usa el viaje asignado (debe estar Programado) y los primeros asientos libres.
   La tabla temporal #Libres sobrevive a los GO de este script. */
DECLARE @ViajeID INT = 16000;  -- CAMBIAR
IF OBJECT_ID('tempdb..#Libres') IS NOT NULL DROP TABLE #Libres;
CREATE TABLE #Libres (Fila INT IDENTITY(1,1) PRIMARY KEY, NumeroAsiento INT);
INSERT #Libres (NumeroAsiento)
SELECT TOP (8) NumeroAsiento
FROM dbo.vw_AsientosDisponibles
WHERE ViajeID = @ViajeID
ORDER BY NumeroAsiento;

IF OBJECT_ID('tempdb..#Control') IS NOT NULL DROP TABLE #Control;
SELECT SYSDATETIME() AS InicioVentas INTO #Control;

DECLARE @i INT = 1, @Asiento INT, @Boleto INT;
WHILE @i <= 5
BEGIN
    SET @Asiento = (SELECT NumeroAsiento FROM #Libres WHERE Fila = @i);
    EXEC dbo.sp_VenderBoleto @ViajeID = @ViajeID, @NumeroAsiento = @Asiento,
         @ClienteID = 1000 + @i, @Canal = 'Web', @Metodo = 'Tarjeta', @BoletoID = @Boleto OUTPUT;
    SET @i += 1;
END
GO

/* ---------- 4) Respaldo DIFERENCIAL ---------- */
BACKUP DATABASE BusRD
TO DISK = 'C:\Backups\BusRD\BusRD_DIF.bak'
WITH DIFFERENTIAL, INIT, NAME = 'BusRD DIFERENCIAL', CHECKSUM, STATS = 10;
GO

/* ---------- 5) Vender 3 boletos más ---------- */
DECLARE @ViajeID INT = 16000;  -- CAMBIAR (mismo viaje)
DECLARE @i INT = 6, @Asiento INT, @Boleto INT;
WHILE @i <= 8
BEGIN
    SET @Asiento = (SELECT NumeroAsiento FROM #Libres WHERE Fila = @i);
    EXEC dbo.sp_VenderBoleto @ViajeID = @ViajeID, @NumeroAsiento = @Asiento,
         @ClienteID = 1000 + @i, @Canal = 'Web', @Metodo = 'Tarjeta', @BoletoID = @Boleto OUTPUT;
    SET @i += 1;
END
GO

/* ---------- 6) Respaldo de LOG ---------- */
BACKUP LOG BusRD
TO DISK = 'C:\Backups\BusRD\BusRD_LOG.trn'
WITH INIT, NAME = 'BusRD LOG', CHECKSUM, STATS = 10;
GO

/* ---------- 7) Anotar la hora exacta y simular el error ----------
   Copiar el valor de HoraAntesDelDelete: es el punto de restauración. */
WAITFOR DELAY '00:00:02';
SELECT CONVERT(VARCHAR(30), SYSDATETIME(), 121) AS HoraAntesDelDelete;
GO

DECLARE @ViajeID INT = 16000;  -- CAMBIAR
SELECT COUNT(*) AS BoletosAntesDelError FROM dbo.Boletos WHERE ViajeID = @ViajeID;
-- El error: se borran primero los pagos (FK) y después los boletos del viaje
DELETE p
FROM dbo.Pagos p
JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.ViajeID = @ViajeID;

DELETE FROM dbo.Boletos WHERE ViajeID = @ViajeID;
SELECT COUNT(*) AS BoletosDespuesDelError FROM dbo.Boletos WHERE ViajeID = @ViajeID;
GO

/* ---------- 8) Respaldo de LOG de cola ---------- */
BACKUP LOG BusRD
TO DISK = 'C:\Backups\BusRD\BusRD_LOG_COLA.trn'
WITH INIT, NAME = 'BusRD LOG COLA', CHECKSUM, STATS = 10;
GO

/* ---------- 9) Restaurar en BusRD_Recuperada hasta antes del DELETE ----------
   Cambiar la hora de STOPAT por la anotada en el paso 7 (formato 'AAAA-MM-DD HH:MM:SS').
   Revisar nombres lógicos con: RESTORE FILELISTONLY FROM DISK = '...FULL.bak' */
USE master;
GO
RESTORE DATABASE BusRD_Recuperada
FROM DISK = 'C:\Backups\BusRD\BusRD_FULL.bak'
WITH MOVE 'BusRD'     TO 'C:\Backups\BusRD\BusRD_Recuperada.mdf',
     MOVE 'BusRD_log' TO 'C:\Backups\BusRD\BusRD_Recuperada_log.ldf',
     NORECOVERY, REPLACE, STATS = 10;

RESTORE DATABASE BusRD_Recuperada
FROM DISK = 'C:\Backups\BusRD\BusRD_DIF.bak'
WITH NORECOVERY, STATS = 10;

RESTORE LOG BusRD_Recuperada
FROM DISK = 'C:\Backups\BusRD\BusRD_LOG.trn'
WITH NORECOVERY;

RESTORE LOG BusRD_Recuperada
FROM DISK = 'C:\Backups\BusRD\BusRD_LOG_COLA.trn'
WITH STOPAT = '2026-10-26 10:00:00',   -- CAMBIAR por la hora anotada en el paso 7
     RECOVERY;
GO

/* ---------- 10) Verificación ----------
   Los 8 boletos vendidos deben existir y los borrados deben haber vuelto. */
USE BusRD_Recuperada;
GO
DECLARE @ViajeID INT = 16000;  -- CAMBIAR
SELECT COUNT(*) AS BoletosRecuperados
FROM dbo.Boletos WHERE ViajeID = @ViajeID;
SELECT COUNT(*) AS VendidosEnLaSesion
FROM dbo.Boletos WHERE ViajeID = @ViajeID AND FechaVenta >= (SELECT TOP (1) InicioVentas FROM #Control);
GO

/* ---------- 11) Política de respaldos propuesta (para el informe) ----------
   Tipo         | Frecuencia                          | Retención   | Motivo
   FULL         | Semanal (domingo 02:00)             | 30 días     | Punto de partida completo
   DIFERENCIAL  | Diaria (lunes a sábado 02:00)       | 14 días     | Restaurar rápido sin muchos archivos
   LOG          | Cada 15 minutos, en horario de venta| 7 días      | Limita la pérdida de datos a 15 minutos
   Verificar cada respaldo con RESTORE VERIFYONLY y probar una restauración al mes. */
