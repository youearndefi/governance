const {
  BN,           // Big Number support
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');
const web3 = require('web3');
const { expect } = require('chai');

const {ZERO_ADDRESS} = constants;
const DEFAULT_WITHDRAWAL_AMOUNT = 1000;
const DEFAULT_PERIOD = 17280;

const YouEarnFundGovernance = artifacts.require('YouEarnFundGovernance');
const TestToken = artifacts.require('TestToken');
const YouEarnStaking = artifacts.require('YouEarnStaking');

let yeFGContractInstance, testTokenInstance, yeStakingInstance;

let governor, withdrawAddress, voter = [];

const BN2Number = bn => bn.toNumber();
const toWei = n => n*1e18;

function proposeAWithdrawal({
    withdrawAddress = withdrawAddress,
    withdrawAmount = DEFAULT_WITHDRAWAL_AMOUNT,
    hash = '',
    from = governor
}) {
    return yeFGContractInstance.propose(withdrawAddress, withdrawAmount, hash, {
        from
    })
}
const voteFn = ({proposalId = proposalId, id, from = voter[0], fnName}) => {
    proposalId = proposalId || id;
    return yeFGContractInstance[fnName](proposalId, {from})
}
contract('YouEarnFundGovernance', accounts => {
    [governor] = accounts;
    [_, ...voter] = accounts;
    beforeEach(async () => {
        //set the minimum required quorum to 3 for testing
        yeFGContractInstance = await YouEarnFundGovernance.new(governor, 3);
        testTokenInstance = await TestToken.new();
        yeStakingInstance = await YouEarnStaking.new(yeFGContractInstance.address);
    })
    describe('deployment', async () => {
        it('should deploy successful', async () => {
            expect(yeFGContractInstance.address).to.not.be(ZERO_ADDRESS);
        })
        it('should return the correct governor', async () => {
            expect(await yeFGContractInstance.getGovernor()).to.be(governor);
        })

    })

    describe('propose', async () => {
        it('should not propose when the sender is not the governor', async () => {
            await expectEvent(proposeAWithdrawal({
                from: accounts[1]
            }), 'Caller is not the governor')
        })
        it('should propose successful', async () => {
            const logs = await proposeAWithdrawal();
            let block = await web3.eth.getBlock("latest")
            expectEvent(logs, 'NewWithdrawProposal', {
                id: 1,
                creator: governor,
                start: block,
                duration: DEFAULT_PERIOD,
                withdrawAddress,
                withdrawAmount: DEFAULT_WITHDRAWAL_AMOUNT
            })
        })
        it('should increate proposalCount', async () => {
            await proposeAWithdrawal();
            await proposeAWithdrawal();
            const currentProposalCount = await yeFGContractInstance.proposalCount.call().then(BN2Number)
            expect(currentProposalCount).to.be.above(1);
        })
    })

    describe('vote', () => {
        let proposalId = 1;
        let tokenBalance = toWei(10000)
        
        const expectVoteLog = (logs, {
            id = proposalId,
            voter = voter[0],
            vote = true,
            weight = tokenBalance
        }) => expectEvent(logs, 'Vote', { id, voter, vote, weight })

        const expectStatToBeAtLeast = async ({_for = 0, against = 0, quorum = 0}) => {
            const [_forPercentage, _againstPercentage, _quorum] = await yeFGContractInstance.getStats(proposalId);
            expect(_forPercentage).to.be.at.least(_for);
            expect(_againstPercentage).to.be.at.least(against);
            expect(_quorum).to.be.at.least(quorum);
        }

        const expectStatByCallback = async (cb) => {
            const [_forPercentage, _againstPercentage, _quorum] = await yeFGContractInstance.getStats(proposalId);
            cb(_forPercentage, _againstPercentage, _quorum);
        }

        const voteForFn = obj => voteFn({fnName: 'voteFor', ...obj})
        const voteAgainstFn = obj => voteFn({fnName: 'voteAgainst', ...obj})


        beforeEach(async () => {
            await proposeAWithdrawal();
        })
        describe('voteFor', async () => {
            
            const expectEventLogInVoteForOnly = async () => expectVoteLog(await voteForFn(), {vote: true})

            describe('should vote successful', async () => {
                
                beforeEach(async () => {
                    for(let i = 0; i < 3; i++){
                        await testTokenInstance.mint(tokenBalance, {from: voter[i]});
                    }
                })

                it('should vote by balance successful', async () => {
                    await expectEventLogInVoteForOnly();
                })

                it('should stake then vote successful', async () => {
                    await yeStakingInstance.stake(tokenBalance, {from: voter[0]});
                    await expectEventLogInVoteForOnly();
                })

                it('should call voteOnFundGovernance to staking contract', async () => {
                    await yeStakingInstance.stake(tokenBalance, {from: voter[0]});
                    await expectEventLogInVoteForOnly();

                })

                it('should vote and count the stat', async () => {
                    await expectEventLogInVoteForOnly();
                    await expectStatToBeAtLeast({
                        for: 10,
                        against: 0,
                        quorum: 1
                    })
                    await voteForFn({
                        from: voter[1]
                    });
                    await expectStatToBeAtLeast({
                        for: 50,
                        against: 0,
                        quorum: 2
                    })
                })

                it('vote against then vote for, should has correct behavior', async () => {
                    await voteAgainstFn();
                    await voteForFn();
                })

                it('should count quorum only one', async () => {
                    await voteForFn({
                        from: voter[1]
                    });
                    await voteForFn({
                        from: voter[1]
                    });
                    await expectStatByCallback((_, __, quorum) => {
                        expect(quorum).to.be(1);
                    })
                })


            })
            describe('should vote unsuccessful', async () => {
                it('should revert when the proposal is not started', async () => {
                     await expectEvent(voteForFn({
                         proposalId: 2
                     }),"The proposal has not started yet");
                })
                it('should revert when the proposal is not ended', async () => {
                      //TODO: close the proposal id 3
                    //   await expectEvent(voteForFn({
                    //      proposalId: 3
                    //  }),"The proposal is ended");
                })
                it('Should not able to vote when the balance is 0', async () => {
                    await expectEvent(voteForFn(),"No balance left to vote");
                });
                
            })
        })
        describe('voteAgainst', async () => {
             const expectEventLogInVoteForOnly = async () => expectVoteLog(await voteAgainstFn(), {vote: false})

            describe('should vote successful', async () => {
                
                beforeEach(async () => {
                    for(let i = 0; i < 3; i++){
                        await testTokenInstance.mint(tokenBalance, {from: voter[i]});
                    }
                })

                it('should vote by balance successful', async () => {
                    await expectEventLogInVoteForOnly();
                })

                it('should stake then vote successful', async () => {
                    await yeStakingInstance.stake(tokenBalance, {from: voter[0]});
                    await expectEventLogInVoteForOnly();
                })

                it('should call voteOnFundGovernance to staking contract', async () => {
                    await yeStakingInstance.stake(tokenBalance, {from: voter[0]});
                    await expectEventLogInVoteForOnly();

                })

                it('should vote and count the stat', async () => {
                    await expectEventLogInVoteForOnly();
                    await expectStatToBeAtLeast({
                        for: 10,
                        against: 0,
                        quorum: 1
                    })
                    await voteAgainstFn({
                        from: voter[1]
                    });
                    await expectStatToBeAtLeast({
                        for: 50,
                        against: 0,
                        quorum: 2
                    })
                })

                it('vote for then vote against, should has correct behavior', async () => {
                    await voteForFn();
                    await voteAgainstFn();
                })

                it('should count quorum only one', async () => {
                    await voteAgainstFn({
                        from: voter[1]
                    });
                    await voteAgainstFn({
                        from: voter[1]
                    });
                    await expectStatByCallback((_, __, quorum) => {
                        expect(quorum).to.be(1);
                    })
                })


            })
            describe('should vote unsuccessful', async () => {
                it('should revert when the proposal is not started', async () => {
                     await expectEvent(voteAgainstFn({
                         proposalId: 2
                     }),"The proposal has not started yet");
                })
                it('should revert when the proposal is not ended', async () => {
                      //TODO: close the proposal id 3
                    //   await expectEvent(voteAgainstFn({
                    //      proposalId: 3
                    //  }),"The proposal is ended");
                })
                it('Should not able to vote when the balance is 0', async () => {
                    await expectEvent(voteAgainstFn(),"No balance left to vote");
                });
                
            })
        })
        
    })

    describe('execute testing', () => {
        //see YouEarnGovernance.test.js
    })

    describe('executeProposal', () => {
        beforeEach(async () => {
            await proposeAWithdrawal();
        })

        const executeProposalFn = (id) => yeFGContractInstance.executeProposal(id);

        describe('should not execute successful', async () => {
            it('should only governor able to call', async () => {
                await expectRevert(executeProposalFn(proposalId), "Caller is not the governor");
            })
            
            it('should not able to call when the proposal is not ended', async () => {
                await expectRevert(executeProposalFn(proposalId), "The proposal has not ended (yet)");
            })
            it('should not able to call when the proposal is closed', async () => {

            })

        })

        describe('should execute successful', async () => {
            const mockVoting = async ({
                expectForPercent = 50,
                expectQuorum = 5
            }) => {
                await proposeAWithdrawal();
                const _proposalId = 2; //should increase to 2 now
                const defaultVoteAmount = toWei(10000);
                const totalVoteAmount = defaultVoteAmount*expectQuorum;
                let actualVoteForPercentage = 0;
                for(let i=0; i< expectQuorum; ++i){
                    await testTokenInstance.mint(defaultVoteAmount, {
                        from: voter[i]
                    });
                    actualVoteForPercentage += defaultVoteAmount*100/totalVoteAmount
                    if(actualVoteForPercentage >= expectForPercent) {
                        await voteFn({
                            proposalId: _proposalId,
                            from: voter[i],
                            fnName: 'voteFor'
                        })
                    };
                }
                
            }
            const getProposalDetail = async (id) => {
                return yeFGContractInstance.getProposalDetail(id);
            }

            it("should passed and receive the funds when the _forPercentage is greater or qual than 50% and met the quorom required", async () => {
                const logs = await mockVoting({
                    expectForPercent: 60,
                    expectQuorum: 5
                })
                expectEvent(logs, 'WithdrawProposalFinished', {
                    id: 2,
                    _for: 60,
                    _against: 40,
                    quorum: 5
                })
                const [isOpening, isPassed] = await getProposalDetail(2);
                expect(isOpening).to.be(false);
                expect(isPassed).to.be(true);
            })
            it("should not be passed when the _forPercentage is less than 50% but the quorom is met", async () => {
                const logs = await mockVoting({
                    expectForPercent: 40,
                    expectQuorum: 5
                })
                const [isOpening, isPassed] = await getProposalDetail(2);
                expect(isOpening).to.be(false);
                expect(isPassed).to.be(false);
            })
            it("should not be passed when the quorom is less than requirement but the _forPercentage is greater than 50%", async () => {
                const logs = await mockVoting({
                    expectForPercent: 50,
                    expectQuorum: 2
                })
                const [isOpening, isPassed] = await getProposalDetail(2);
                expect(isOpening).to.be(false);
                expect(isPassed).to.be(false);
            })
            it("should not be passed when the quorom and the _forPercentage requirements is not met", async () => {
                const logs = await mockVoting({
                    expectForPercent: 20,
                    expectQuorum: 2
                })
                const [isOpening, isPassed] = await getProposalDetail(2);
                expect(isOpening).to.be(false);
                expect(isPassed).to.be(false);
            })

        })
        
    })

    describe('election testing', () => {
        const voteInElection = (candidateId, from = voter[0]) => {
            return yeFGContractInstance.voteInElection(candidateId, {from});
        }
        beforeEach(async () => {

        })
        it('should not be able to vote when not start the election ', async () => {
            await voteInElection();
        })
        describe('addCandidate', async () => {
            async function addCandidate({
                id = 1,
                address = accounts[4],
                name = 'Test',
                lectureURL = 'https://ahvsa.com',
                from = voter[0]
            }){
                await yeFGContractInstance.addCandidate(id, address, name, lectureURL, {from});
            }
            describe("should not be able to addCandidate", async () => {
                it("should throw an error when caller is not the authority", async () => {
                    await addCandidate({
                        from: accounts[8]
                    });
                })

                it("should throw an error when addCandidate is not during the election prepairing time", async () => {
                    await addCandidate()
                })

                it("The candidate id cannot be dublicated", async () => {
                    await addCandidate();
                    await expectRevert(addCandidate(), "This candidate id is used");
                })
            })
            describe("should add the candidate successful and correctly", async () => {
                it("should add the candidate successful and correctly", async () => {
                    await addCandidate()

                })
            })
        })

        describe('voteInElection', async () => {
            describe("shoud vote not be successful", async () => {

            })
            describe("should vote successful and correctly", async () => {
                it("should notice the staking contract correctly", async () => {

                })
            })
        })

        describe('executeElection', async () => {
            it("should be executed only when the election is ended", async () => {

            })
            
            it("should call the execution only once", async () => {

            })

            it("should execute successful and correctly", async () => {

            })
        })

    })


})