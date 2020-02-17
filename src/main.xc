// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 64                  //image height
#define  IMWD 64                  //image width
#define  numWorkerThreads 8       //number of workers

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0] : port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0] : port p_sda = XS1_PORT_1F;

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

// A function that returns the number of alive cells surrounding a specified cell
int liveNeighbors(uchar picture[IMWD][IMHT / numWorkerThreads + 2], int x, int y) {
    int noLiveCells = 0;

    if(picture[(x + 1) % IMWD][y] == 0xFF) {
        noLiveCells++;
    }
    if(picture[(x - 1 + IMWD) % IMWD][y] == 0xFF) {
        noLiveCells++;
    }
    if(picture[x][(y + 1) % IMHT] == 0xFF) {
        noLiveCells++;
    }
    if(picture[x][(y - 1 + IMHT) % IMHT] == 0xFF) {
        noLiveCells++;
    }
    if(picture[(x + 1) % IMWD][(y + 1) % IMHT] == 0xFF) {
        noLiveCells++;
    }
    if(picture[(x + 1) % IMWD][(y - 1 + IMHT) % IMHT] == 0xFF) {
        noLiveCells++;
    }
    if(picture[(x - 1 + IMWD) % IMWD][(y + 1) % IMHT] == 0xFF) {
        noLiveCells++;
    }
    if(picture[(x - 1 + IMWD) % IMWD][(y - 1 + IMHT) % IMHT] == 0xFF) {
        noLiveCells++;
    }

    return noLiveCells;
}

//  Define a communication interface i
//  typedef interface i {
//      void send(int id, int numberDeep);
//
//      void receive(uchar picture[IMWD][IMHT]);
//} i;

// READ BUTTONS and send button pattern to distributor
void buttonListener(in port b, chanend toUser) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if ((r==13) || (r==14))     // if either button is pressed
    toUser <: r;             // send button pattern to userAnt
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
//      printf( "-%4.1d ", line[ x ] ); //show image values
    }
//    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

// Worker thread
void workerThreadSub(chanend workerThread, int id) {
//    uchar picture[IMWD][IMHT];
//    uchar editedPicture[IMWD][IMHT];

    uchar picture[IMWD][IMHT / numWorkerThreads + 2];       // Declaring the array that is used to store the
                                                            //   data sent by the distributor
    uchar editedPicture[IMWD][IMHT / numWorkerThreads];     // Array used to store the edited image

    int numberOfLines = IMHT / numWorkerThreads;            // Number of rows each worker is responsible for

    while(1) {
        for (int y = 0; y < numberOfLines + 2; y++) {
            for (int x = 0; x < IMWD; x++) {
                workerThread :> picture[x][y];              // Fetch data from distributor
            }
        }

        for (int y = 0; y < numberOfLines; y++) {
            for (int x = 0; x < IMWD; x++) {
                int noLiveCells = liveNeighbors(picture, x, y + 1);  // Calculate number of live cells

                if( picture[x][y + 1] == 0xFF) {                    // If cell is alive
                    if(noLiveCells == 2 || noLiveCells == 3) {
                        editedPicture[x][y] = (uchar) ( picture[x][y + 1] ^ 0x00);
                    } else {
                        editedPicture[x][y] = (uchar) ( picture[x][y + 1] ^ 0xFF);
                    }
                } else if (picture[x][y + 1] == 0x00) {
                    if(noLiveCells == 3) {
                        editedPicture[x][y] = (uchar) ( picture[x][y + 1] ^ 0xFF);
                    } else {
                        editedPicture[x][y] = (uchar) ( picture[x][y + 1] ^ 0x00);
                    }
                }
                workerThread <: editedPicture[x][y];             // Send edited image with updated cells back to distributor
            }
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend fromButtons, out port LEDs,
        chanend workerThread[numWorkerThreads])
{
    uchar val;
    uchar picture[IMWD][IMHT];
    uchar picture2[IMWD][IMHT];

    int buttonInput;
    int tiltValue = 0;
    int buttonExit = 0;
    int isLooped = 0;
    uchar flashLED = 0;
    int numberOfLines = IMHT / numWorkerThreads;
    int numRounds;
    int numLiveCells;

    timer t;
    unsigned int startTime;
    unsigned int endTime;
    unsigned int resultTime;

    //Starting up and wait for tilting of the xCore-200 Explorer
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
    printf( "Waiting for Button Press...\n" );
    while (buttonExit == 0) {
        select {
          case fromButtons :> buttonInput:
              if (buttonInput == 14) {              // If button SW1 is pressed, start the game
                  isLooped = 1;

                  LEDs <: 4;                        // Set LED to green to signify reading of the image
                  printf( "Processing...\n" );
                  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
                    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
                      c_in :> val;                    //read the pixel value
                      picture[x][y] = val;
                      picture2[x][y] = picture[x][y];
                    }
                  }
                  t :>  startTime;                   // Start the timer
              } else if (buttonInput == 13) {        // If button SW2 is pressed, stop the game
                  isLooped = 0;
                  buttonExit = 1;
              }
              break;
          default:
              break;
        }

        fromAcc :> tiltValue;                         // Fetch tilt value from orientation thread

        //      printf("isLooped %d\n", isLooped);
        //      printf("tiltValue %d\n", tiltValue);

        int rowNumber = 0;

        if (isLooped == 1 && tiltValue == 0) {

            for (int workerNumber = 0; workerNumber < numWorkerThreads; workerNumber++) {  // For each worker thread
                for (int y = 0; y < numberOfLines + 2; y++) {  // For each row the worker is responsible for, plus the one below and above (GHOST ROWS)
                    for (int x = 0 ; x < IMWD; x++) {  // For each pixel per row
                        rowNumber = y + (numberOfLines * workerNumber) - 1; // Starting row the worker is responsible for
                        if (rowNumber == -1) {  // If the previous function returns -1, that means its trying to fetch the ghost row of the 0th row
                            rowNumber = IMHT - 1;  // Ghost row of row 0 is the bottom row
                        } else if (rowNumber == IMHT) {
                            rowNumber = 0;
                        }
                        workerThread[workerNumber] <: picture[x][rowNumber]; // Send pixels to the worker thread
                    }
                }
            }

            flashLED ^= 1;   // Flash the LED green
            LEDs <: flashLED;

            for (int workerNumber = 0; workerNumber < numWorkerThreads; workerNumber++) {
              int additionalDepth = workerNumber * numberOfLines;
              for (int y = 0; y < numberOfLines; y++) {
                  for (int x = 0; x < IMWD; x++) {
                      workerThread[workerNumber] :> picture2[x][additionalDepth + y];  // Receive the modified image from each worker and store inside picture2 array
                  }
              }
            }

            for (int y = 0; y < IMHT; y++) {
              for (int x = 0; x < IMWD; x++) {
                  picture[x][y] = picture2[x][y];  // Set the original image to equal modified image
              }
            }

            printf( "\nOne processing round completed...\n" );

            numRounds++; // Increment round number

            fromAcc :> tiltValue; // Felt tilt value from orientation thread

            int currentlyTilted = 0;

            if (tiltValue == 1) {
              currentlyTilted = 1;
            }

            numLiveCells = 0;

            while (tiltValue == 1) { // While the board is tilted, enter the while loop
                if(currentlyTilted == 1) {
                    printf("GAME PAUSED\n"); // Pause the game

                    t :> endTime; // Fetch the time from the timer
                    resultTime += (endTime - startTime) / 100000;
                    startTime = endTime;

                for (int y = 0; y < IMHT; y++) {    // Count the number of live cells on the image
                    for (int x = 0; x< IMWD; x++) {
                        if (picture2[x][y] == 0xFF) {
                            numLiveCells++;
                        }
                    }
                }

                printf("Time taken = %u ms\n", resultTime);
                printf("Number of rounds processed = %d\n", numRounds);
                printf("Number of live cells = %d\n", numLiveCells);

                }
                LEDs <: 8; // Red LED

                // printf("tiltValue %d\n", tiltValue);

                fromAcc :> tiltValue;

                currentlyTilted = 0;
            }
        }

        // Used in testing to test for 100 rounds
        if(numRounds == 400) {
            break;
        }
    }

    // Stop the timer and print how long the whole thing took
    t :> endTime;
    resultTime += (endTime - startTime) / 100000;
    printf("Time taken = %u ms\n", resultTime);

    LEDs <: 2; // Blue
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD; x++) {
            c_out <: (uchar) (picture2[x][y]); // Send the modified pixels out to be written
        }
    }
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
    int res;
    uchar line[ IMWD ];

    //Open PGM file
    printf( "DataOutStream: Start...\n" );
    res = _openoutpgm( outfname, IMWD, IMHT );
    if( res ) {
        printf( "DataOutStream: Error opening %s\n.", outfname );
        return;
    }

    //Compile each line of the image and write the image line-by-line
    for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x++ ) {
            c_in :> line[ x ];
        }
        _writeoutline( line, IMWD );
        //    printf( "DataOutStream: Line written...\n" );
    }

    //Close the PGM image
    _closeoutpgm();
    printf( "DataOutStream: Done...\n" );
    return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
    i2c_regop_res_t result;
    char status_data = 0;
    //int tilted = 0;

    // Configure FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
    if (result != I2C_REGOP_SUCCESS) {
        printf("I2C write reg failed\n");
    }

    // Enable FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
    if (result != I2C_REGOP_SUCCESS) {
        printf("I2C write reg failed\n");
    }

    //Probe the orientation x-axis forever
    while (1) {

        //check until new orientation data is available
        do {
            status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
        } while (!status_data & 0x08);

        //get new x-axis tilt value
        int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

        //send signal to distributor after first tilt
        if (x > 30) {
            toDist <: 1;
        } else  {
            toDist <: 0;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

chan c_inIO, c_outIO, c_control, buttonsToUser, workerThread[numWorkerThreads];    //extend your channel definitions here

//interface i workerThread[numWorkerThreads];

par {
    on tile[0] : buttonListener(buttons, buttonsToUser);
    on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0] : orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0] : DataInStream("64x64.pgm", c_inIO);          //thread to read in a PGM image
    on tile[0] : DataOutStream("testout.pgm", c_outIO);       //thread to write out a PGM image
    on tile[0] : distributor(c_inIO, c_outIO, c_control, buttonsToUser, leds, workerThread); //thread to coordinate work on image

    // Start all the worker threads on tile 1
    par (int i = 0; i < numWorkerThreads; i++) {
        on tile[1] : workerThreadSub(workerThread[i], i);
    }
  }

  return 0;
}
