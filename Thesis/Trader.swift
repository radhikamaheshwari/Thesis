//
//  trader.swift
//  Thesis
//
//  Created by Charlie on 1/8/19.
//  Copyright © 2019 Charlie. All rights reserved.
//

import Foundation
import GameplayKit
import Accelerate


class Trader {
    let traderID: Int
    let traderType: Int
    let cancelProb: Float
    var localBook: [Int:[String:Int]]
    var cancelCollector: [[String:Int]]
    var numQuotes: Int
    var quoteRange: Int
    var position: Int
    var cashFlow: Int
    var cashFlowTimeStamps: [Int]
    var cashFlows: [Int]
    var positions: [Int]
    var quoteCollector: [[String:Int]]
    var orderID: Int
    var maxQuantity: Int
    var buySellProb: Float
    var timeDelta: Int
    var lambda: Double
    var rng: SystemRandomNumberGenerator
    var testRandomNumbers: [Float]
    let percentOfWealth: Float
    var wealth: Double
    var dice: GKRandomDistribution
    var wealthString: String
    let generalFileManager = FileManager()
    var maxWealth: Int
    var takerQ: Int
    var takerQDirection: Int
    
    init(trader: Int, traderType: Int, numQuotes: Int, quoteRange: Int, cancelProb: Float, maxQuantity: Int, buySellProb: Float, lambda: Double, percentWealth: Float, initW: Double) {
        self.traderID = trader
        self.traderType = traderType
        self.localBook = [:]
        self.cancelCollector = []
        self.numQuotes = numQuotes
        self.quoteRange = quoteRange
        self.position = 1
        self.cashFlow = 0
        self.cashFlowTimeStamps = []
        self.cashFlows = []
        self.positions = []
        self.quoteCollector = []
        self.orderID = 0
        self.cancelProb = cancelProb
        self.maxQuantity = maxQuantity
        self.buySellProb = buySellProb
        self.lambda = lambda
        self.timeDelta = 0
        self.rng = SystemRandomNumberGenerator()
        self.testRandomNumbers = []
        self.percentOfWealth = percentWealth
        self.wealth = initW
        self.maxWealth = Int(wealth * 0.12)
        self.dice = GKRandomDistribution(lowestValue: 1, highestValue: 2)
        self.wealthString = "TraderID,Wealth,TimeStamp\n"
        self.takerQ = Int.random(in: 1...20)
        self.takerQDirection = Int.random(in: 1...2)
    }
    
    func makeTimeDelta(lambda: Double) {
        let rExp = randExp(rate: lambda) + 1.0
        let i = floor(rExp)
        let iq = i * Double(self.maxQuantity)
        let tDelta = Int(iq)
        timeDelta = tDelta
    }
    
    func randExp(rate: Double) -> Double {
        return -1.0 / rate * log(Double.random(in: 0...1, using: &rng))
    }
    
    func makeAddOrder(time: Int, side: Int, price: Int, quantity: Int) -> [String:Int] {
        orderID += 1
        let addOrder = ["orderID": orderID, "ID": 0, "traderID": traderID, "timeStamp": time, "type": 1, "quantity": quantity, "side": side, "price": price]
        return addOrder
    }
    
    func makeCancelOrder(existingOrder: [String:Int], time: Int) -> [String:Int] {
        let cancelOrder = ["orderID": existingOrder["orderID"]!, "ID": existingOrder["ID"]!, "traderID": traderID, "timeStamp": time, "type": 2, "quantity": existingOrder["quantity"]!, "side": existingOrder["side"]!, "price": existingOrder["price"]!]
        return cancelOrder
    }
    
    func cumulateCashFlow(timeStamp: Int, price: Double) {
        cashFlowTimeStamps.append(timeStamp)
        cashFlows.append(cashFlow)
        positions.append(position)
        wealth = Double(cashFlow) + (Double(position) * price)
        let newLine = "\(traderID),\(wealth),\(timeStamp)\n"
        wealthString.append(contentsOf: newLine)
    }
    
    func confirmTradeLocal(confirmOrder: [String:Int], price: Double) {
        // Update cashflow and position
        if confirmOrder["side"] == 1 {
            cashFlow -= confirmOrder["price"]! * confirmOrder["quantity"]!
            position += confirmOrder["quantity"]!
        }
        else {
            cashFlow += confirmOrder["price"]! * confirmOrder["quantity"]!
            position -= confirmOrder["quantity"]!
        }
        // Modify/remove order from local book
        let localOrder = localBook[confirmOrder["orderID"]!]
        if confirmOrder["quantity"]! == localOrder!["quantity"] {
            localBook.removeValue(forKey: localOrder!["orderID"]!)
        }
        else {
            localBook[localOrder!["orderID"]!]!["quantity"]! -= confirmOrder["quantity"]!
        }
        cumulateCashFlow(timeStamp: confirmOrder["timeStamp"]!, price: price)
    }
    
    func bulkCancel(timeStamp: Int) {
        cancelCollector.removeAll()
        for x in localBook.keys {
            if Float.random(in: 0..<1) <= cancelProb {
                cancelCollector.append(makeCancelOrder(existingOrder: localBook[x]!, time: timeStamp))
            }
        }
        for c in cancelCollector {
            localBook.removeValue(forKey: c["orderID"]!)
        }
    }
    
    func providerProcessSignal(timeStamp: Int, topOfBook: [String:Int], buySellProb: Float) -> [String:Int?] {
        var price: Int
        var side: Int
        let lambda = Double.random(in: 0..<200)
        var order: [String:Int]
        if dice.nextInt() == 1 {
            side = 1
            price = choosePriceFromExp(side: side, insidePrice: topOfBook["bestAsk"]!, lambda: lambda)
        }
        else {
            side = 2
            price = choosePriceFromExp(side: side, insidePrice: topOfBook["bestBid"]!, lambda: lambda)
        }
        order = makeAddOrder(time: timeStamp, side: side, price: price, quantity: Int.random(in: 1...maxQuantity))
        localBook[order["orderID"]!] = order
        return order
    }
    
    func choosePriceFromExp(side: Int, insidePrice: Int, lambda: Double) -> Int {
        var plug: Int
        var price: Int
        plug = Int(lambda * log(Double.random(in: 0..<1)))
        if side == 1 {
            price = insidePrice - (-plug) - 1
            return price
        }
        else {
            price = insidePrice + (-plug) + 1
            return price
        }
    }
    
    func mmProcessSignal(timeStamp: Int, topOfBook: [String:Int?], buySellProb: Float) -> [[String:Int?]] {
        quoteCollector.removeAll()
        var prices = Array<Int>()
        var side: Int
        /*:
         */
        //////////////////////////////////////////////
        // Start of changes for this branch
        var bidPrices = Array<Int>()
        var askPrices = Array<Int>()
        let spread = topOfBook["bestAsk"]!! - topOfBook["bestBid"]!!
        let marketPrice = (topOfBook["bestAsk"]!! + topOfBook["bestBid"]!!) / 2
        let maxBidPrice = Int(marketPrice) - Int(spread / 2) - Int(max(pow(Double(abs(position)), 0.3), 1))
        let minBidPrice = maxBidPrice - quoteRange
        let minAskPrice = Int(marketPrice) + Int(spread / 2) + Int(max(pow(Double(abs(position)), 0.3), 1))
        let maxAskPrice = minAskPrice + quoteRange

        for _ in 1 ... numQuotes / 2 {
            bidPrices.append(Int.random(in: minBidPrice...maxBidPrice))
        }
        for _ in 1 ... numQuotes / 2 {
            askPrices.append(Int.random(in: minAskPrice...maxAskPrice))
        }
        
        for price in bidPrices {
            let order = makeAddOrder(time: timeStamp, side: 1, price: price, quantity: maxQuantity)
            localBook[order["orderID"]!] = order
            quoteCollector.append(order)
        }
        
        for price in askPrices {
            let order = makeAddOrder(time: timeStamp, side: 2, price: price, quantity: maxQuantity)
            localBook[order["orderID"]!] = order
            quoteCollector.append(order)
        }
        return quoteCollector
    }
        // End of changes for this branch
        ///////////////////////////////////////////////

/*:

        // This creates a buy order (buySellProb = .5 is equal probability of buy or sell)
        if dice.nextInt() == 1 {
            let maxBidPrice = topOfBook["bestBid"]!
            let minBidPrice = maxBidPrice! - quoteRange
            for _ in 1 ... numQuotes {
                prices.append(Int.random(in: minBidPrice...maxBidPrice!))
            }
            side = 1
        }
        // This creates a sell order
        else {
            let minAskPrice = topOfBook["bestAsk"]!
            let maxAskPrice = minAskPrice! + quoteRange
            for _ in 1 ... Int.random(in: 1...numQuotes) {
                prices.append(Int.random(in: minAskPrice!...maxAskPrice))
            }
            side = 2
        }
        for price in prices {
            let order = makeAddOrder(time: timeStamp, side: side, price: price, quantity: Int.random(in: 1...maxQuantity))
            localBook[order["orderID"]!] = order
            quoteCollector.append(order)
        }
        return quoteCollector
    }

 */
        
    
    func mtProcessSignal(timeStamp: Int) -> [String:Int] {
        
        if self.takerQ == 0 {
            self.takerQDirection = Int.random(in: 1...2)
            self.takerQ = Int.random(in: 1...20)
        }
        
        if self.takerQDirection == 1 {
            let order = makeAddOrder(time: timeStamp, side: 1, price: 2000000, quantity: Int.random(in: 1...maxQuantity))
            self.takerQ -= 1
            return order
        }
        else {
            let order = makeAddOrder(time: timeStamp, side: 2, price: 0, quantity: Int.random(in: 1...maxQuantity))
            self.takerQ -= 1
            return order
        }
    }
    
    func addWealthToCsv(filePath: String) {
        if generalFileManager.fileExists(atPath: filePath) {
            // create file handler
            let fh = FileHandle(forWritingAtPath: filePath)
            // seek to end of file
            fh?.seekToEndOfFile()
            // convert sip string to Data type
            let data = wealthString.data(using: String.Encoding.utf8, allowLossyConversion: false)
            // write to end of file
            fh?.write(data!)
            // close the file handler
            fh?.closeFile()
            wealthString.removeAll()
        }
        else {
            do {
                try wealthString.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
                wealthString.removeAll()
            } catch {
                print("Failed to write sip to file.")
                print("\(error)")
            }
        }
    }
}

