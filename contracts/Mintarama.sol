pragma solidity ^0.4.18;

contract MintaramaData {

    uint256 constant public DEV_REWARD_PERCENT = 40 ether;
    uint256 constant public MNTP_REWARD_PERCENT = 30 ether;
    uint256 constant public REF_BONUS_PERCENT = 20 ether;
    uint256 constant public BIG_PROMO_PERCENT = 5 ether;
    uint256 constant public QUICK_PROMO_PERCENT = 5 ether;

    uint128 public BIG_PROMO_BLOCK_INTERVAL = 9999;
    uint128 public QUICK_PROMO_BLOCK_INTERVAL = 100;
    uint256 public PROMO_MIN_PURCHASE = 100 ether;

    int64 public PRICE_SPEED_PERCENT = 5;
    int64 public PRICE_SPEED_TOKEN_BLOCK = 10000;


    uint256 constant public TOKEN_PRICE_INITIAL = 0.01 ether;

    mapping(address => uint256) internal _userTokenBalances;
    mapping(address => uint256) internal _refBalances;
    mapping(address => uint256) internal _rewardPayouts;
    mapping(address => uint256) internal _promoBonuses;

    mapping(bytes32 => bool) public _administrators;
    
    uint256 internal _totalSupply;
    int128 internal _realTokenPrice;

    uint256 public totalIncomeFeePercent = 100 ether;
    uint256 public minRefTokenAmount = 1 ether;
    uint256 public initBlockNum;
    uint256 public bonusPerMntp;
    uint256 public devReward;
    uint256 public currentBigPromoBonus;
    uint256 public currentQuickPromoBonus;
    uint256 public totalCollectedPromoBonus;

}

contract Mintarama {

    IMNTP _mntpToken;
    MintaramaData _data;

    uint256 constant internal MAGNITUDE = 2**64;


    uint256 constant public DEV_REWARD_PERCENT = 40 ether;
    uint256 constant public MNTP_REWARD_PERCENT = 30 ether;
    uint256 constant public REF_BONUS_PERCENT = 20 ether;
    uint256 constant public BIG_PROMO_PERCENT = 5 ether;
    uint256 constant public QUICK_PROMO_PERCENT = 5 ether;

    uint128 public BIG_PROMO_BLOCK_INTERVAL = 9999;
    uint128 public QUICK_PROMO_BLOCK_INTERVAL = 100;
    uint256 public PROMO_MIN_PURCHASE = 100 ether;

    int64 public PRICE_SPEED_PERCENT = 5;
    int64 public PRICE_SPEED_TOKEN_BLOCK = 10000;


    uint256 constant public TOKEN_PRICE_INITIAL = 0.01 ether;

    mapping(address => uint256) internal _userTokenBalances;
    mapping(address => uint256) internal _refBalances;
    mapping(address => uint256) internal _rewardPayouts;
    mapping(address => uint256) internal _promoBonuses;

    mapping(bytes32 => bool) public _administrators;
    
    uint256 internal _totalSupply;
    int128 internal _realTokenPrice;

    uint256 public totalIncomeFeePercent = 100 ether;
    uint256 public minRefTokenAmount = 1 ether;
    uint256 public initBlockNum;
    uint256 public bonusPerMntp;
    uint256 public devReward;
    uint256 public currentBigPromoBonus;
    uint256 public currentQuickPromoBonus;
    uint256 public totalCollectedPromoBonus;
    

    uint64 public initTime;
    uint64 public expirationPeriodDays;
    
    bool public isActive;
    
    event onTokenPurchase(address indexed userAddress, uint256 incomingEth, uint256 tokensMinted, address indexed referredBy);
    
    event onTokenSell(address indexed userAddress, uint256 tokensBurned, uint256 ethEarned);
    
    event onReinvestment(address indexed userAddress, uint256 ethReinvested, uint256 tokensMinted);
    
    event onWithdraw(address indexed userAddress, uint256 ethWithdrawn); 

    event onWithdrawDevReward(address indexed toAddress, uint256 ethWithdrawn); 

    event onWinQuickPromo(address indexed userAddress, uint256 ethWon);    
   
    event onWinBigPromo(address indexed userAddress, uint256 ethWon);    


    // only people with tokens
    modifier onlyContractUsers() {
        require(getLocalTokenBalance(msg.sender) > 0);
        _;
    }
    
    // only people with profits
    modifier onlyRewardOwners() {
        require(getCurrentUserReward(true, true) > 0);
        _;
    }

    // administrators can:
    // -> change the name of the contract
    // -> change the PoS difficulty (How many tokens it costs to hold a masternode, in case it gets crazy high later)
    // they CANNOT:
    // -> take funds
    // -> disable withdrawals
    // -> kill the contract
    // -> change the price of tokens
    modifier onlyAdministrator() {
        require(_administrators[keccak256(msg.sender)]);
        _;
    }

    modifier onlyActive() {
        require(isActive);
        _;
    }


    function Mintarama(address mntpTokenAddress, uint64 expirationInDays) public {
        _mntpToken = IMNTP(mntpTokenAddress);
        _administrators[keccak256(msg.sender)] = true;
        _realTokenPrice = convert256ToReal(TOKEN_PRICE_INITIAL);

        initBlockNum = block.number;
        initTime = uint64(now);

        expirationPeriodDays = initTime + expirationInDays * 1 days;

        isActive = true;
    }
    
    function setTotalSupply(uint256 val) onlyAdministrator public {
        uint256 tokenAmount = _mntpToken.balanceOf(address(this));
        
        require(_totalSupply == 0 && tokenAmount == val);

        _totalSupply = val;
    }

    function setBigPromoInterval(uint128 val) onlyAdministrator public {
        BIG_PROMO_BLOCK_INTERVAL = val;
    }

    function setQuickPromoInterval(uint128 val) onlyAdministrator public {
        QUICK_PROMO_BLOCK_INTERVAL = val;
    }

    function setPriceSpeed(uint64 speedPercent, uint64 speedTokenBlock) onlyAdministrator public {
        PRICE_SPEED_PERCENT = int64(speedPercent);
        PRICE_SPEED_TOKEN_BLOCK = int64(speedTokenBlock);
    }

    function setMinRefTokenAmount(uint256 val) onlyAdministrator public {
        minRefTokenAmount = val;
    }

    function switchActive() onlyAdministrator public {
        isActive = !isActive;
    }

    function setTotalIncomeFeePercent(uint256 val) onlyAdministrator public {
        require(val > 0 && val <= 100 ether);

        totalIncomeFeePercent = val;
    }

    function finish() onlyAdministrator public {
        require(uint(now) >= expirationPeriodDays);
        
        _mntpToken.transfer(msg.sender, getRemainTokenAmount());   
        msg.sender.transfer(getTotalEthBalance());

        isActive = false;
    }

    /**
     * Converts incoming eth to tokens
     */
    function buy(address refAddress) onlyActive public payable returns(uint256) {
        return purchaseTokens(msg.value, refAddress);
    }

    /**
     * sell tokens for eth
     */
    function sell(uint256 tokenAmount) onlyActive onlyContractUsers public returns(uint256) {
        
        if (tokenAmount > getUserLocalTokenBalance() || tokenAmount == 0) return;

        uint256 ethAmount = 0; uint256 totalFeeEth = 0; uint256 tokenPrice = 0;
        (ethAmount, totalFeeEth, tokenPrice) = estimateSellOrder(tokenAmount);

        subUserTokens(msg.sender, tokenAmount);

        msg.sender.transfer(ethAmount);

        updateTokenPrice(-convert256ToReal(tokenAmount));

        distributeFee(totalFeeEth, 0x0);
       
        onTokenSell(msg.sender, tokenAmount, ethAmount);

        return ethAmount;
    }   

    /**
     * Fallback function to handle ethereum that was send straight to the contract
     */
    function() onlyActive public payable {
        purchaseTokens(msg.value, 0x0);
    }

    /**
     * Converts all of caller's reward to tokens.
     */
    function reinvest() onlyActive onlyRewardOwners public {
        uint256 reward = getRewardAndPrepareWithdraw();

        uint256 tokens = purchaseTokens(reward, 0x0);
        
        onReinvestment(msg.sender, reward, tokens);
    }

     /**
     * Withdraws all of the callers earnings.
     */
    function withdraw() onlyActive onlyRewardOwners public {

        uint256 reward = getRewardAndPrepareWithdraw();
        
        msg.sender.transfer(reward);
        
        onWithdraw(msg.sender, reward);
    }

    function withdrawDevReward(address to) onlyAdministrator public {
        require(devReward > 0);

        to.transfer(devReward);

        devReward = 0;

        onWithdrawDevReward(to, devReward);
    }
    

    /* HELPERS */  

    function getCurrentTokenPrice() public view returns(uint256) {
        return convertRealTo256(_realTokenPrice);
    }

    function getRealCurrentTokenPrice() public view returns(int128) {
        return _realTokenPrice;
    }

    function getTotalEthBalance() public view returns(uint256) {
        return this.balance;
    }
    
    function getTotalTokenSupply() public view returns(uint256) {
        return _totalSupply;
    }

    function getRemainTokenAmount() public view returns(uint256) {
        return _mntpToken.balanceOf(address(this));
    }

    function getTotalTokenSold() public view returns(uint256) {
        return _totalSupply - getRemainTokenAmount();
    }

    function getLocalTokenBalance(address userAddress) public view returns(uint256) {
        return _userTokenBalances[userAddress];
    }
    
    function getUserLocalTokenBalance() public view returns(uint256) {
        return getLocalTokenBalance(msg.sender);
    }    

    function isRefAvailable(address refAddress) public view returns(bool) {
        return getLocalTokenBalance(refAddress) >= minRefTokenAmount;
    }

    function isCurrentUserRefAvailable() public view returns(bool) {
        return isRefAvailable(msg.sender);
    }

    function getCurrentUserReward(bool incRefBonus, bool incPromoBonus) public view returns(uint256) {
        uint256 reward = bonusPerMntp * _userTokenBalances[msg.sender];
        reward = ((reward < _rewardPayouts[msg.sender]) ? 0 : SafeMath.sub(reward, _rewardPayouts[msg.sender])) / MAGNITUDE;
        
        if (incRefBonus) reward = SafeMath.add(reward, _refBalances[msg.sender]);
        if (incPromoBonus) reward = SafeMath.add(reward, _promoBonuses[msg.sender]);
        
        return reward;
    }
  

    function get1TokenSellPrice() public view returns(uint256) {
        uint256 tokenAmount = 1 ether;

        uint256 ethAmount = 0; uint256 totalFeeEth = 0; uint256 tokenPrice = 0;
        (ethAmount, totalFeeEth, tokenPrice) = estimateSellOrder(tokenAmount);

        return ethAmount;
    }
    
    function get1TokenBuyPrice() public view returns(uint256) {
        uint256 ethAmount = 1 ether;

        uint256 tokenAmount = 0; uint256 totalFeeEth = 0; uint256 tokenPrice = 0;
        (tokenAmount, totalFeeEth, tokenPrice) = estimateBuyOrder(ethAmount);  

        return SafeMath.div(ethAmount * 1 ether, tokenAmount);
    }

    function calculateReward(uint256 tokenAmount) public view returns(uint256) {
        return (uint256) ((int256)(bonusPerMntp * tokenAmount)) / MAGNITUDE;
    }  


    function estimateBuyOrder(uint256 ethAmount) public view returns(uint256, uint256, uint256) {
        uint256 totalTokenFee = calcPercent(ethToTokens(ethAmount, true, true) - ethToTokens(ethAmount, true, false), totalIncomeFeePercent);
        require(totalTokenFee > 0);

        uint256 totalFeeEth = tokensToEth(totalTokenFee, true, true);
        require(totalFeeEth > 0 && ethAmount > totalFeeEth);

        uint256 tokenAmount = ethToTokens(ethAmount, true, false);
        require(tokenAmount > 0);

        uint256 tokenPrice = SafeMath.div(ethAmount * 1 ether, tokenAmount);

        return (tokenAmount, totalFeeEth, tokenPrice);
    }
    

    function estimateSellOrder(uint256 tokenAmount) public view returns(uint256, uint256, uint256) {
        uint256 ethAmount = tokensToEth(tokenAmount, false, false);
        require(ethAmount > 0);

        uint256 totalFeeEth = calcPercent(tokensToEth(tokenAmount, false, true) - tokensToEth(tokenAmount, false, false), totalIncomeFeePercent);
        require(totalFeeEth > 0 && ethAmount > totalFeeEth);

        uint256 tokenPrice = SafeMath.div(ethAmount * 1 ether, tokenAmount);

        return (ethAmount, totalFeeEth, tokenPrice);
    }

    function getUserMaxPurchase(address userAddress) public view returns(uint256) {
        return _mntpToken.balanceOf(userAddress) - getLocalTokenBalance(userAddress);
    }
    
    function getCurrentUserMaxPurchase() public view returns(uint256) {
        return getUserMaxPurchase(msg.sender);
    }

    function getDevReward() public view returns(uint256) {
        return devReward;
    }

    function getPromoBonus() public view returns(uint256) {
        return _promoBonuses[msg.sender];
    }

    function getRefBonus() public view returns(uint256) {
        return _refBalances[msg.sender];
    }
   
    function getBlockNumSinceInit() public view returns(uint256) {
        return block.number - initBlockNum;
    }

    // INTERNAL FUNCTIONS
    
    function purchaseTokens(uint256 ethAmount, address refAddress) internal returns(uint256) {

        uint256 tokenAmount = 0; uint256 totalFeeEth = 0; uint256 tokenPrice = 0;
        (tokenAmount, totalFeeEth, tokenPrice) = estimateBuyOrder(ethAmount);

        //user has to have at least equal amount of tokens which he's willing to buy 
        require(getCurrentUserMaxPurchase() >= tokenAmount);

        require(tokenAmount > 0 && (SafeMath.add(tokenAmount, getTotalTokenSold()) > getTotalTokenSold()));

        if (refAddress == msg.sender || !isRefAvailable(refAddress)) refAddress = 0x0;

        uint256 userRewardBefore = getCurrentUserReward(false, false);

        distributeFee(totalFeeEth, refAddress);
        
        addUserTokens(msg.sender, tokenAmount);

        // the user is not going to receive any reward for the current purchase
        _rewardPayouts[msg.sender] = SafeMath.add(_rewardPayouts[msg.sender], SafeMath.sub(getCurrentUserReward(false, false), userRewardBefore) * MAGNITUDE);
        
        checkAndSendPromoBonus(tokenAmount);
        
        updateTokenPrice(convert256ToReal(tokenAmount));
        
        onTokenPurchase(msg.sender, ethAmount, tokenAmount, refAddress);
        
        return tokenAmount;
    }

    function getRewardAndPrepareWithdraw() internal returns(uint256) {

        uint256 reward = getCurrentUserReward(false, false);
        
        // update dividend tracker
        _rewardPayouts[msg.sender] = SafeMath.add(_rewardPayouts[msg.sender], reward * MAGNITUDE);
        
        // add ref bonus
        reward = SafeMath.add(reward, _refBalances[msg.sender]);
        _refBalances[msg.sender] = 0;

        // add promo bonus
        reward = SafeMath.add(reward, _promoBonuses[msg.sender]);
        _promoBonuses[msg.sender] = 0;

        return reward;
    }

    function checkAndSendPromoBonus(uint256 purchaedTokenAmount) internal {
        if (purchaedTokenAmount < PROMO_MIN_PURCHASE) return;

        uint256 blockNumSinceInit = getBlockNumSinceInit();

        if (blockNumSinceInit % QUICK_PROMO_BLOCK_INTERVAL == 0) sendQuickPromoBonus();
        if (blockNumSinceInit % BIG_PROMO_BLOCK_INTERVAL == 0) sendBigPromoBonus();
    }

    function sendQuickPromoBonus() internal {
        _promoBonuses[msg.sender] = SafeMath.add(_promoBonuses[msg.sender], currentQuickPromoBonus);
        
        onWinQuickPromo(msg.sender, currentQuickPromoBonus);

        currentQuickPromoBonus = 0;
    }

    function sendBigPromoBonus() internal {
        _promoBonuses[msg.sender] = SafeMath.add(_promoBonuses[msg.sender], currentBigPromoBonus);

        onWinBigPromo(msg.sender, currentBigPromoBonus);

        currentBigPromoBonus = 0;        
    }

    function distributeFee(uint256 totalFeeEth, address refAddress) internal {
        addProfitPerShare(totalFeeEth, refAddress);
        addDevReward(totalFeeEth);
        addBigPromoBonus(totalFeeEth);
        addQuickPromoBonus(totalFeeEth);
    }

    function addProfitPerShare(uint256 totalFeeEth, address refAddress) internal {
        uint256 refBonus = calcRefBonus(totalFeeEth);
        uint256 totalShareReward = calcTotalShareRewardFee(totalFeeEth);

        if (refAddress != 0x0) {
            _refBalances[refAddress] = SafeMath.add(_refBalances[refAddress], refBonus);
        } else {
            totalShareReward = SafeMath.add(totalShareReward, refBonus);
        }

        if (getTotalTokenSold() == 0) {
            devReward = SafeMath.add(devReward, totalShareReward);
        } else {
            bonusPerMntp = SafeMath.add(bonusPerMntp, (totalShareReward * MAGNITUDE) / getTotalTokenSold());
        }
    }

    function addDevReward(uint256 totalFeeEth) internal {
        devReward = SafeMath.add(devReward, calcDevReward(totalFeeEth));
    }    

    function addBigPromoBonus(uint256 totalFeeEth) internal {
        uint256 bonus = calcBigPromoBonus(totalFeeEth);
        currentBigPromoBonus = SafeMath.add(currentBigPromoBonus, bonus);
        totalCollectedPromoBonus = SafeMath.add(totalCollectedPromoBonus, bonus);
    }

    function addQuickPromoBonus(uint256 totalFeeEth) internal {
        uint256 bonus = calcQuickPromoBonus(totalFeeEth);
        currentQuickPromoBonus = SafeMath.add(currentQuickPromoBonus, bonus);
        totalCollectedPromoBonus = SafeMath.add(totalCollectedPromoBonus, bonus);
    }    

    function addUserTokens(address user, uint256 tokenAmount) internal {
        _userTokenBalances[user] = SafeMath.add(_userTokenBalances[user], tokenAmount);  
        _mntpToken.transfer(msg.sender, tokenAmount);   
    }

    function subUserTokens(address user, uint256 tokenAmount) internal {
        _userTokenBalances[user] = SafeMath.sub(_userTokenBalances[user], tokenAmount);  
        _mntpToken.transferFrom(user, address(this), tokenAmount);    
    }

    function updateTokenPrice(int128 realTokenAmount) internal {
        _realTokenPrice = calc1RealTokenRateFromRealTokens(realTokenAmount);
    }

    function ethToTokens(uint256 ethAmount, bool isBuy, bool isHalfPrice) internal view returns(uint256) {
        int128 realEthAmount = convert256ToReal(ethAmount);
        int128 t0 = RealMath.div(realEthAmount, _realTokenPrice);
        int128 s = RealMath.div( getRealPriceSpeed(), RealMath.toReal(isHalfPrice ? 2 : 1) );
        int128 tns = RealMath.mul(t0, s);
        int128 exptns = RealMath.exp( RealMath.mul(tns, RealMath.toReal(isBuy ? int64(1) : int64(-1))) );

        int128 tn = t0;

        for (uint i = 0; i < 10; i++) {

            int128 tn1 = RealMath.div(
                RealMath.mul( RealMath.mul(RealMath.ipow(tn, 2), s), exptns ) + t0,
                RealMath.mul( exptns, RealMath.toReal(1) + tns )
            );

            if (RealMath.abs(tn-tn1) < RealMath.fraction(1, 1e18)) break;

            tn = tn1;
        }


        return convertRealTo256(tn);
    }

    function tokensToEth(uint256 tokenAmount, bool isBuy, bool isHalfPrice) internal view returns(uint256) {
        int128 realTokenAmount = convert256ToReal(tokenAmount);
        int128 s = RealMath.div( getRealPriceSpeed(), RealMath.toReal(isHalfPrice ? 2 : 1) );
        int128 expArg = RealMath.mul(RealMath.mul(realTokenAmount, s), RealMath.toReal(isBuy ? int64(1) : int64(-1)));
        
        int128 realEthAmountFor1Token = RealMath.mul(_realTokenPrice, RealMath.exp(expArg));
        int128 realEthAmount = RealMath.mul(realTokenAmount, realEthAmountFor1Token);

        return convertRealTo256(realEthAmount);
    }

    function calc1RealTokenRateFromRealTokens(int128 realTokenAmount) internal view returns(int128) {
        int128 expArg = RealMath.mul(realTokenAmount, getRealPriceSpeed());

        return RealMath.mul(_realTokenPrice, RealMath.exp(expArg));
    }
    
    function getRealPriceSpeed() public view returns(int128) {
        return RealMath.div(RealMath.fraction(PRICE_SPEED_PERCENT, 100), RealMath.toReal(PRICE_SPEED_TOKEN_BLOCK));
    }


    function calcTotalShareRewardFee(uint256 totalFee) internal pure returns(uint256) {
        return calcPercent(totalFee, MNTP_REWARD_PERCENT);
    }
    
    function calcRefBonus(uint256 totalFee) internal pure returns(uint256) {
        return calcPercent(totalFee, REF_BONUS_PERCENT);
    }

    function calcDevReward(uint256 totalFee) internal pure returns(uint256) {
        return calcPercent(totalFee, DEV_REWARD_PERCENT);
    }

    function calcQuickPromoBonus(uint256 totalFee) internal pure returns(uint256) {
        return calcPercent(totalFee, QUICK_PROMO_PERCENT);
    }    

    function calcBigPromoBonus(uint256 totalFee) internal pure returns(uint256) {
        return calcPercent(totalFee, BIG_PROMO_PERCENT);
    }        
    
    function calcPercent(uint256 amount, uint256 percent) public pure returns(uint256) {
        return SafeMath.div(SafeMath.mul(SafeMath.div(amount, 100), percent), 1 ether);
    }

    /*
    * Converts real num to uint256. Works only with positive numbers.
    */
    function convertRealTo256(int128 realVal) internal pure returns(uint256) {
        int128 roundedVal = RealMath.fromReal(RealMath.mul(realVal, RealMath.toReal(1e14)));

        return SafeMath.mul(uint256(roundedVal), uint256(1e4));
    }

    /*
    * Converts uint256 to real num.
    */
    function convert256ToReal(uint256 val) internal pure returns(int128) {
        return RealMath.fraction(int64(SafeMath.div(val, 1e4)), 1e14);
    }
}


contract IMNTP {
    function balanceOf(address _owner) public constant returns (uint256);
    function transfer(address _to, uint256 _value) public returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) public returns(bool);
}

library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function mul(uint128 a, uint128 b) internal pure returns (uint128) {
        if (a == 0) {
            return 0;
        }
        uint128 c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function div(uint128 a, uint128 b) internal pure returns (uint128) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint128 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    /**
    * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }

    function add(uint128 a, uint128 b) internal pure returns (uint128) {
        uint128 c = a + b;
        assert(c >= a);
        return c;
    }

    function sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }        
}


library RealMath {
    
    /**
     * How many total bits are there?
     */
    int256 constant REAL_BITS = 128;
    
    /**
     * How many fractional bits are there?
     */
    int256 constant REAL_FBITS = 64;
    
    /**
     * How many integer bits are there?
     */
    int256 constant REAL_IBITS = REAL_BITS - REAL_FBITS;
    
    /**
     * What's the first non-fractional bit
     */
    int128 constant REAL_ONE = int128(1) << REAL_FBITS;
    
    /**
     * What's the last fractional bit?
     */
    int128 constant REAL_HALF = REAL_ONE >> 1;
    
    /**
     * What's two? Two is pretty useful.
     */
    int128 constant REAL_TWO = REAL_ONE << 1;
    
    /**
     * And our logarithms are based on ln(2).
     */
    int128 constant REAL_LN_TWO = 762123384786;
    
    /**
     * It is also useful to have Pi around.
     */
    int128 constant REAL_PI = 3454217652358;
    
    /**
     * And half Pi, to save on divides.
     * TODO: That might not be how the compiler handles constants.
     */
    int128 constant REAL_HALF_PI = 1727108826179;
    
    /**
     * And two pi, which happens to be odd in its most accurate representation.
     */
    int128 constant REAL_TWO_PI = 6908435304715;
    
    /**
     * What's the sign bit?
     */
    int128 constant SIGN_MASK = int128(1) << 127;
    

    /**
     * Convert an integer to a real. Preserves sign.
     */
    function toReal(int64 ipart) internal pure returns (int128) {
        return int128(ipart) * REAL_ONE;
    }
    
    /**
     * Convert a real to an integer. Preserves sign.
     */
    function fromReal(int128 real_value) internal pure returns (int64) {
        return int64(real_value / REAL_ONE);
    }
    
    /**
     * Round a real to the nearest integral real value.
     */
    function round(int128 real_value) internal pure returns (int128) {
        // First, truncate.
        int64 ipart = fromReal(real_value);
        if ((fractionalBits(real_value) & (uint64(1) << (REAL_FBITS - 1))) > 0) {
            // High fractional bit is set. Round up.
            if (real_value < int128(0)) {
                // Rounding up for a negative number is rounding down.
                ipart -= 1;
            } else {
                ipart += 1;
            }
        }
        return toReal(ipart);
    }
    
    /**
     * Get the absolute value of a real. Just the same as abs on a normal int128.
     */
    function abs(int128 real_value) internal pure returns (int128) {
        if (real_value > 0) {
            return real_value;
        } else {
            return -real_value;
        }
    }
    
    /**
     * Returns the fractional bits of a real. Ignores the sign of the real.
     */
    function fractionalBits(int128 real_value) internal pure returns (uint64) {
        return uint64(abs(real_value) % REAL_ONE);
    }
    
    /**
     * Get the fractional part of a real, as a real. Ignores sign (so fpart(-0.5) is 0.5).
     */
    function fpart(int128 real_value) internal pure returns (int128) {
        // This gets the fractional part but strips the sign
        return abs(real_value) % REAL_ONE;
    }

    /**
     * Get the fractional part of a real, as a real. Respects sign (so fpartSigned(-0.5) is -0.5).
     */
    function fpartSigned(int128 real_value) internal pure returns (int128) {
        // This gets the fractional part but strips the sign
        int128 fractional = fpart(real_value);
        return real_value < 0 ? -fractional : fractional;
    }
    
    /**
     * Get the integer part of a fixed point value.
     */
    function ipart(int128 real_value) internal pure returns (int128) {
        // Subtract out the fractional part to get the real part.
        return real_value - fpartSigned(real_value);
    }
    
    /**
     * Multiply one real by another. Truncates overflows.
     */
    function mul(int128 real_a, int128 real_b) internal pure returns (int128) {
        // When multiplying fixed point in x.y and z.w formats we get (x+z).(y+w) format.
        // So we just have to clip off the extra REAL_FBITS fractional bits.
        return int128((int256(real_a) * int256(real_b)) >> REAL_FBITS);
    }
    
    /**
     * Divide one real by another real. Truncates overflows.
     */
    function div(int128 real_numerator, int128 real_denominator) internal pure returns (int128) {
        // We use the reverse of the multiplication trick: convert numerator from
        // x.y to (x+z).(y+w) fixed point, then divide by denom in z.w fixed point.
        return int128((int256(real_numerator) * REAL_ONE) / int256(real_denominator));
    }
    
    /**
     * Create a real from a rational fraction.
     */
    function fraction(int64 numerator, int64 denominator) internal pure returns (int128) {
        return div(toReal(numerator), toReal(denominator));
    }
    
    // Now we have some fancy math things (like pow and trig stuff). This isn't
    // in the RealMath that was deployed with the original Macroverse
    // deployment, so it needs to be linked into your contract statically.
    
    /**
     * Raise a number to a positive integer power in O(log power) time.
     * See <https://stackoverflow.com/a/101613>
     */
    function ipow(int128 real_base, int64 exponent) internal pure returns (int128) {
        if (exponent < 0) {
            // Negative powers are not allowed here.
            revert();
        }
        
        // Start with the 0th power
        int128 real_result = REAL_ONE;
        while (exponent != 0) {
            // While there are still bits set
            if ((exponent & 0x1) == 0x1) {
                // If the low bit is set, multiply in the (many-times-squared) base
                real_result = mul(real_result, real_base);
            }
            // Shift off the low bit
            exponent = exponent >> 1;
            // Do the squaring
            real_base = mul(real_base, real_base);
        }
        
        // Return the final result.
        return real_result;
    }
    
    /**
     * Zero all but the highest set bit of a number.
     * See <https://stackoverflow.com/a/53184>
     */
    function hibit(uint256 val) internal pure returns (uint256) {
        // Set all the bits below the highest set bit
        val |= (val >>  1);
        val |= (val >>  2);
        val |= (val >>  4);
        val |= (val >>  8);
        val |= (val >> 16);
        val |= (val >> 32);
        val |= (val >> 64);
        val |= (val >> 128);
        return val ^ (val >> 1);
    }
    
    /**
     * Given a number with one bit set, finds the index of that bit.
     */
    function findbit(uint256 val) internal pure returns (uint8 index) {
        index = 0;
        // We and the value with alternating bit patters of various pitches to find it.
        
        if (val & 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA != 0) {
            // Picth 1
            index |= 1;
        }
        if (val & 0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC != 0) {
            // Pitch 2
            index |= 2;
        }
        if (val & 0xF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0 != 0) {
            // Pitch 4
            index |= 4;
        }
        if (val & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00 != 0) {
            // Pitch 8
            index |= 8;
        }
        if (val & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000 != 0) {
            // Pitch 16
            index |= 16;
        }
        if (val & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000 != 0) {
            // Pitch 32
            index |= 32;
        }
        if (val & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000 != 0) {
            // Pitch 64
            index |= 64;
        }
        if (val & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000 != 0) {
            // Pitch 128
            index |= 128;
        }
    }
    
    /**
     * Shift real_arg left or right until it is between 1 and 2. Return the
     * rescaled value, and the number of bits of right shift applied. Shift may be negative.
     *
     * Expresses real_arg as real_scaled * 2^shift, setting shift to put real_arg between [1 and 2).
     *
     * Rejects 0 or negative arguments.
     */
    function rescale(int128 real_arg) internal pure returns (int128 real_scaled, int64 shift) {
        if (real_arg <= 0) {
            // Not in domain!
            revert();
        }
        
        // Find the high bit
        int64 high_bit = findbit(hibit(uint256(real_arg)));
        
        // We'll shift so the high bit is the lowest non-fractional bit.
        shift = high_bit - int64(REAL_FBITS);
        
        if (shift < 0) {
            // Shift left
            real_scaled = real_arg << -shift;
        } else if (shift >= 0) {
            // Shift right
            real_scaled = real_arg >> shift;
        }
    }
    
    /**
     * Calculate the natural log of a number. Rescales the input value and uses
     * the algorithm outlined at <https://math.stackexchange.com/a/977836> and
     * the ipow implementation.
     *
     * Lets you artificially limit the number of iterations.
     *
     * Note that it is potentially possible to get an un-converged value; lack
     * of convergence does not throw.
     */
    function lnLimited(int128 real_arg, int max_iterations) internal pure returns (int128) {
        if (real_arg <= 0) {
            // Outside of acceptable domain
            revert();
        }
        
        if (real_arg == REAL_ONE) {
            // Handle this case specially because people will want exactly 0 and
            // not ~2^-39 ish.
            return 0;
        }
        
        // We know it's positive, so rescale it to be between [1 and 2)
        int128 real_rescaled;
        int64 shift;
        (real_rescaled, shift) = rescale(real_arg);
        
        // Compute the argument to iterate on
        int128 real_series_arg = div(real_rescaled - REAL_ONE, real_rescaled + REAL_ONE);
        
        // We will accumulate the result here
        int128 real_series_result = 0;
        
        for (int64 n = 0; n < max_iterations; n++) {
            // Compute term n of the series
            int128 real_term = div(ipow(real_series_arg, 2 * n + 1), toReal(2 * n + 1));
            // And add it in
            real_series_result += real_term;
            if (real_term == 0) {
                // We must have converged. Next term is too small to represent.
                break;
            }
            // If we somehow never converge I guess we will run out of gas
        }
        
        // Double it to account for the factor of 2 outside the sum
        real_series_result = mul(real_series_result, REAL_TWO);
        
        // Now compute and return the overall result
        return mul(toReal(shift), REAL_LN_TWO) + real_series_result;
        
    }
    
    /**
     * Calculate a natural logarithm with a sensible maximum iteration count to
     * wait until convergence. Note that it is potentially possible to get an
     * un-converged value; lack of convergence does not throw.
     */
    function ln(int128 real_arg) internal pure returns (int128) {
        return lnLimited(real_arg, 100);
    }
    

     /**
     * Calculate e^x. Uses the series given at
     * <http://pages.mtu.edu/~shene/COURSES/cs201/NOTES/chap04/exp.html>.
     *
     * Lets you artificially limit the number of iterations.
     *
     * Note that it is potentially possible to get an un-converged value; lack
     * of convergence does not throw.
     */
    function expLimited(int128 real_arg, int max_iterations) internal pure returns (int128) {
        // We will accumulate the result here
        int128 real_result = 0;
        
        // We use this to save work computing terms
        int128 real_term = REAL_ONE;
        
        for (int64 n = 0; n < max_iterations; n++) {
            // Add in the term
            real_result += real_term;
            
            // Compute the next term
            real_term = mul(real_term, div(real_arg, toReal(n + 1)));
            
            if (real_term == 0) {
                // We must have converged. Next term is too small to represent.
                break;
            }
            // If we somehow never converge I guess we will run out of gas
        }
        
        // Return the result
        return real_result;
        
    }


    /**
     * Calculate e^x with a sensible maximum iteration count to wait until
     * convergence. Note that it is potentially possible to get an un-converged
     * value; lack of convergence does not throw.
     */
    function exp(int128 real_arg) internal pure returns (int128) {
        return expLimited(real_arg, 100);
    }
    
    /**
     * Raise any number to any power, except for negative bases to fractional powers.
     */
    function pow(int128 real_base, int128 real_exponent) internal pure returns (int128) {
        if (real_exponent == 0) {
            // Anything to the 0 is 1
            return REAL_ONE;
        }
        
        if (real_base == 0) {
            if (real_exponent < 0) {
                // Outside of domain!
                revert();
            }
            // Otherwise it's 0
            return 0;
        }
        
        if (fpart(real_exponent) == 0) {
            // Anything (even a negative base) is super easy to do to an integer power.
            
            if (real_exponent > 0) {
                // Positive integer power is easy
                return ipow(real_base, fromReal(real_exponent));
            } else {
                // Negative integer power is harder
                return div(REAL_ONE, ipow(real_base, fromReal(-real_exponent)));
            }
        }
        
        if (real_base < 0) {
            // It's a negative base to a non-integer power.
            // In general pow(-x^y) is undefined, unless y is an int or some
            // weird rational-number-based relationship holds.
            revert();
        }
        
        // If it's not a special case, actually do it.
        return exp(mul(real_exponent, ln(real_base)));
    }
    
    /**
     * Compute the square root of a number.
     */
    function sqrt(int128 real_arg) internal pure returns (int128) {
        return pow(real_arg, REAL_HALF);
    }
    
    /**
     * Compute the sin of a number to a certain number of Taylor series terms.
     */
    function sinLimited(int128 real_arg, int64 max_iterations) internal pure returns (int128) {
        // First bring the number into 0 to 2 pi
        // TODO: This will introduce an error for very large numbers, because the error in our Pi will compound.
        // But for actual reasonable angle values we should be fine.
        real_arg = real_arg % REAL_TWO_PI;
        
        int128 accumulator = REAL_ONE;
        
        // We sum from large to small iteration so that we can have higher powers in later terms
        for (int64 iteration = max_iterations - 1; iteration >= 0; iteration--) {
            accumulator = REAL_ONE - mul(div(mul(real_arg, real_arg), toReal((2 * iteration + 2) * (2 * iteration + 3))), accumulator);
            // We can't stop early; we need to make it to the first term.
        }
        
        return mul(real_arg, accumulator);
    }
    
    /**
     * Calculate sin(x) with a sensible maximum iteration count to wait until
     * convergence.
     */
    function sin(int128 real_arg) internal pure returns (int128) {
        return sinLimited(real_arg, 15);
    }
    
    /**
     * Calculate cos(x).
     */
    function cos(int128 real_arg) internal pure returns (int128) {
        return sin(real_arg + REAL_HALF_PI);
    }
    
    /**
     * Calculate tan(x). May overflow for large results. May throw if tan(x)
     * would be infinite, or return an approximation, or overflow.
     */
    function tan(int128 real_arg) internal pure returns (int128) {
        return div(sin(real_arg), cos(real_arg));
    }
     
}