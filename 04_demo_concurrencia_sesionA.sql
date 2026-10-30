/* =========================================================
   04_demo_concurrencia_sesionA.sql  -  VENTANA A (SSMS #1)
   Ejecutar SOLO el bloque indicado, en el momento indicado.
   Usar los mismos valores en las dos ventanas (viaje, asiento y cliente).
   ========================================================= */

/* PASO 0 (una sola vez): copia para reproducir la doble venta.
   La copia no debe tener el índice UX_Boletos_AsientoActivo, porque si lo
   tiene, la segunda venta falla por clave duplicada y no hay doble venta.
   Crear la carpeta C:\Backups\BusRD\ antes de ejecutar.

   BACKUP DATABASE BusRD TO DISK = 'C:\Backups\BusRD\copia.bak' WITH INIT;
   RESTORE DATABASE BusRD_Copia FROM DISK = 'C:\Backups\BusRD\copia.bak'
       WITH MOVE 'BusRD'     TO 'C:\Backups\BusRD\BusRD_Copia.mdf',
            MOVE 'BusRD_log' TO 'C:\Backups\BusRD\BusRD_Copia_log.ldf', REPLACE;
   USE BusRD_Copia;
   DROP INDEX UX_Boletos_AsientoActivo ON dbo.Boletos;
   (Si los nombres lógicos no coinciden, revisar con RESTORE FILELISTONLY.)
*/

/* ---------- PARTE 1: reproducción con v0 (en BusRD_Copia) ---------- */
USE BusRD_Copia;
GO
DECLARE @ViajeID INT = 16000, @Asiento INT = 12, @Cliente INT = 1000;  -- CAMBIAR por los datos del grupo
-- Ejecutar con F5. Dentro de los 10 segundos siguientes, ejecutar el bloque de la ventana B.
EXEC dbo.sp_VenderBoleto_v0 @ViajeID = @ViajeID, @NumeroAsiento = @Asiento,
     @ClienteID = @Cliente, @Canal = 'Taquilla', @Metodo = 'Efectivo';

-- Evidencia (ejecutar cuando ambas ventanas terminen)
SELECT BoletoID, ViajeID, NumeroAsiento, ClienteID, Canal, Precio, Estado, FechaVenta
FROM dbo.Boletos
WHERE ViajeID = @ViajeID AND NumeroAsiento = @Asiento AND Estado = 'Activo';
-- Resultado esperado: 2 filas activas para el mismo asiento.
GO

/* ---------- PARTE 2: procedimiento nuevo (en BusRD) ---------- */
USE BusRD;
GO
DECLARE @ViajeID INT = 16000, @Asiento INT = 12, @Cliente INT = 1000, @Boleto INT;  -- CAMBIAR; el asiento debe estar libre
-- Ejecutar con F5. Esta sesión mantiene el bloqueo 10 segundos (@SimularDemora = 1).
EXEC dbo.sp_VenderBoleto @ViajeID = @ViajeID, @NumeroAsiento = @Asiento,
     @ClienteID = @Cliente, @Canal = 'Taquilla', @Metodo = 'Efectivo',
     @SimularDemora = 1, @BoletoID = @Boleto OUTPUT;
SELECT @Boleto AS BoletoGenerado;
-- Resultado esperado: un número de boleto. Esta venta sí queda vigente.
-- Antes de repetir la demo, anular el boleto con sp_AnularBoleto.
