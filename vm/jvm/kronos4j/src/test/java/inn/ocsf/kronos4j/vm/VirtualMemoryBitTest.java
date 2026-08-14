package inn.ocsf.kronos4j.vm;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class VirtualMemoryBitTest {

        private VirtualMemory memory;

        @BeforeEach
        public void setUp() {
            // Выделяем 64 байта памяти перед каждым тестом и обнуляем её
            memory = new VirtualMemory(16);
        }

        @Test
        public void testBasicWriteAndRead() {
            int adr = 0;
            int bitOffset = 10;
            int size = 5;
            int valueToWrite = 0b10101; // 21 в десятичной

            // Записываем 5 бит по смещению 10
            memory.bbp(adr, bitOffset, size, valueToWrite);

            // Считываем обратно и проверяем
            int readValue = memory.bbu(adr, bitOffset, size);
            assertEquals(valueToWrite, readValue, "Считанное значение должно совпадать с записанным");
        }

        @Test
        public void testReadWithMasking() {
            // Вручную пишем в память байт со всеми установленными битами (0xFF)
            memory.store(0, 1,  new byte[] { (byte) 0xFF });

            // Читаем 4 бита с нулевого смещения
            int res = memory.bbu(0, 0, 4);
            assertEquals(0x0F, res, "Должно вернуться 15 (0b1111), так как размер ограничен 4 битами");
        }

        @Test
        public void testBitOffsetAcrossBytes() {
            int adr = 4;
            int bitOffset = 13; // Смещение внутри qword
            int size = 12;      // Размер пересекает границу байта
            int valueToWrite = 0xABC; // 1010 1011 1100

            memory.bbp(adr, bitOffset, size, valueToWrite);

            int readValue = memory.bbu(adr, bitOffset, size);
            assertEquals(valueToWrite, readValue, "Значение должно корректно проходить сквозь границы байтов");
        }

        @Test
        public void testOverwritingExistingBits() {
            int adr = 0;
            int bitOffset = 0;

            // Сначала пишем 0xFFFFFFFF в первые 32 бита (dword)
            memory.bbp(adr, bitOffset, 32, 0xFFFFFFFF);

            // Перезаписываем только средние 8 бит значением 0x00
            memory.bbp(adr, 8, 8, 0x00);

            // Проверяем, что остальные биты не повредились
            assertEquals(0xFF, memory.bbu(adr, 0, 8), "Первые 8 бит должны остаться 0xFF");
            assertEquals(0x00, memory.bbu(adr, 8, 8), "Средние 8 бит должны стать 0x00");
            assertEquals(0xFF, memory.bbu(adr, 16, 8), "Следующие 8 бит должны остаться 0xFF");
        }

        @Test
        public void testAddressShiftHandling() {
            // Тест проверяет логику (i >> 5), которая сдвигает базовый адрес adr на каждые 32 бита i
            int adr = 0;
            int bitOffset = 40; // 40 >> 5 дает +1 к индексу байта. 40 & 0x1F дает 8 бит смещения внутри qword
            int size = 8;
            int value = 0x55;

            memory.bbp(adr, bitOffset, size, value);

            // Значение должно прочитаться по тому же смещению
            assertEquals(value, memory.bbu(adr, bitOffset, size));
        }

}
