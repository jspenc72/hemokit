module Main where

import           Control.Concurrent (threadDelay, forkIO)
import           Control.Monad
import           Data.IORef
import           System.Environment
import           System.IO
import           Test.Robot
import           Text.Show.Pretty (ppShow)

import           Hemokit

import           Hemokit.Internal.Utils (untilNothing)


main :: IO ()
main = do
  args <- getArgs
  let model = if "--developer" `elem` args then Developer else Consumer

  devices <- getEmotivDevices

  putStrLn $ "AvailableDevices:\n" ++ ppShow devices

  device <- openEmotivDevice model $ case reverse devices of d:_ -> d
                                                             []  -> error "no Epoc devices found"

  conn <- connect
  xy <- newIORef (0,0)

  void . forkIO . forever $ do
    (x, y) <- readIORef xy
    print (x, y)
    writeIORef xy (0, 0)
    runRobotWith conn (moveBy ((-x) `quot` 10) (y `quot` 10))
    threadDelay 10000

  void $ untilNothing (readEmotiv device) $ \(state, _) -> do

    -- print (qualities state)
    print state
    -- putStrLn $ show (gyroX state) ++ " " ++ show (gyroY state)
    hFlush stdout

    modifyIORef' xy $ \(x,y) -> (x + gyroX state, y + gyroY state)
