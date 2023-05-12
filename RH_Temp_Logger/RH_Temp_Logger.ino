#include <SoftwareSerial.h>
#include "DHT.h"

#include <SD.h>
#include "RTClib.h"
RTC_DS1307 RTC;

#define DHTPIN 2
#define DHTTYPE DHT22
#define BLUETOOTH_SPEED 9600

const int sd_chipSelect = 10;
SoftwareSerial mySerial(5, 6); // RX, TX
volatile bool sdcard_exist = false;
DHT dht(DHTPIN, DHTTYPE);

void printTime()
{
  DateTime now = RTC.now();
  char timeString[20];
  sprintf(timeString, "%d-%d-%d %02d:%02d:%02d\n",
          now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
  Serial.print(timeString);
}

void dateTime(uint16_t* date, uint16_t* time) {
  DateTime now = RTC.now();

  // return date using FAT_DATE macro to format fields
  *date = FAT_DATE(now.year(), now.month(), now.day());

  // return time using FAT_TIME macro to format fields
  *time = FAT_TIME(now.hour(), now.minute(), now.second());
}

void genTodayCsv(char *str, int strLen)
{
  DateTime now = RTC.now();
  // Be aware of max string len for SD card file name
  sprintf(str, "%d%02d%02d.csv", 
          now.year(), now.month(), now.day());
}

void sdCardLogging(float temp, float rh)
{
  char str[100];
  char fileName[40];
  genTodayCsv(fileName, sizeof(fileName));
  // Create file
  if (!SD.exists(fileName))
  {
    // Create file
    //put this next line *Right Before* any file open line:
    SdFile::dateTimeCallback(dateTime);
    File dataFile = SD.open(fileName, FILE_WRITE);
    sprintf(str, "Time(YYYY-MM-DD HH:MM:SS),Temperature(°C),Relative Humidity(Percent)");
    if (dataFile)
    {
      dataFile.println(str);
      dataFile.close();
      //Serial.println("Created a new CSV file.");
    }
  }
  else
  {
    // Data
    DateTime now = RTC.now();
    //put this next line *Right Before* any file open line:
    SdFile::dateTimeCallback(dateTime);
    File dataFile = SD.open(fileName, FILE_WRITE);
    sprintf(str, "%d-%d-%d %02d:%02d:%02d,%d.%02d,%d.%02d", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second(), (int)temp, (int)(temp * 100) % 100, (int)rh, (int)(rh * 100) % 100);
    if (dataFile)
    {
      dataFile.println(str);
      dataFile.close();
      //Serial.println("Continue writing on a CSV file.");
    }
  }
}

void setup()
{
  // RTC setting
  RTC.begin();
  //RTC.adjust(DateTime(__DATE__, __TIME__));

  Serial.begin(9600);
  mySerial.begin(BLUETOOTH_SPEED);
  dht.begin();

  // SD Card setup
  if (!SD.begin(sd_chipSelect))
  {
    Serial.println("Card failed, or not present");
    sdcard_exist = false;
  }
  else{
    sdcard_exist = true;
  }
}

void loop()
{
  delay(1000);

  float h = dht.readHumidity();
  float t = dht.readTemperature();

  if (isnan(h) || isnan(t))
  {
    Serial.println("Failed to read from DHT sensor!\n");
    return;
  }

  String data = "H:" + String(h, 2) + " T:" + String(t, 2) + "\n";
  Serial.print(data);
  char charBuf[50];
  data.toCharArray(charBuf, 50);
  int bytesSent = mySerial.write(charBuf);

  // Logger
  if (sdcard_exist){
    sdCardLogging(t, h);
  }
}
