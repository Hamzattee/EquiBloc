// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title GigsHub
 * @dev A contract to manage gigs, applications, and payouts.
 */
contract GigsHub is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GIG_OWNER_ROLE = keccak256("GIG_OWNER_ROLE");

    /// @dev Total number of gigs created.
    uint public gigsCount;

    /// @dev Total number of applications submitted.
    uint public appCount;

    /// @dev Mapping of gig ID to Gigs struct.
    mapping(uint => Gigs) public allGigs;

    /// @dev Mapping of application ID to Application struct.
    mapping(uint => Application) private allApp;

    mapping(address => uint256[]) private userGigs;
    mapping(address => uint256[]) private userApplications;

    /// @dev Structure representing a gig.
    struct Gigs {
        uint256 gigId;
        address owner;
        address assignedApplicant;
        string img;
        string description;
        uint256 bounty;
        string[] kpis;
        bool userSelected;
        bool paid;
    }

    /// @dev Structure representing an application to a gig.
    struct Application {
        uint256 appId;
        uint256 gigId;
        address applicant;
        string coverLetter;
        bool selected;
    }

    /// @notice Reverts if the provided amount is invalid (zero).
    error InvalidAmount();

    /// @notice Reverts if the provided ID is invalid.
    error InvalidId();

    /// @notice Emitted when a new gig is created.
    /// @param creator The address of the gig creator.
    /// @param description The description of the gig.
    /// @param amount The bounty amount associated with the gig.
    event GigCreated(
        address indexed creator,
        string description,
        uint256 amount
    );

    /// @notice Emitted when a worker is assigned to a gig.
    /// @param user The address of the assigned worker.
    /// @param gigId The ID of the gig to which the worker is assigned.
    event GigAssigned(address indexed user, uint256 gigId);

    /// @notice Emitted when a gig is paid out.
    /// @param gigId The ID of the gig that was paid out.
    /// @param owner The address of the gig owner.
    /// @param worker The address of the worker who received the payment.
    /// @param amount The amount of Ether paid out.
    event GigPaidOut(
        uint256 gigId,
        address indexed owner,
        address indexed worker,
        uint256 amount
    );

    /// @notice Emitted when funds are withdrawn from the contract.
    /// @param by The address of the entity withdrawing the funds.
    /// @param amount The amount of Ether withdrawn.
    event FundsWithdrawn(address indexed by, uint256 amount);

    /// @notice Emitted when Ether is received by the contract.
    /// @param sender The address of the sender.
    /// @param amount The amount of Ether received.
    event Received(address indexed sender, uint256 amount);

    /**
     * @notice Constructor to disable initializers.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with default admin and pauser roles.
     * @param defaultAdmin The address to be granted the DEFAULT_ADMIN_ROLE.
     * @param pauser The address to be granted the PAUSER_ROLE.
     */
    function initialize(
        address defaultAdmin,
        address pauser
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
    }

    /**
     * @notice Creates a new gig with a specified image, description, and KPIs.
     * @param _img The image URL associated with the gig.
     * @param _description The description of the gig.
     * @param _kpis The key performance indicators for the gig.
     */
    function createGig(
        string calldata _img,
        string calldata _description,
        string[] calldata _kpis
    ) external payable {
        if (msg.value == 0) {
            revert InvalidAmount();
        }
        gigsCount++;
        allGigs[gigsCount] = Gigs(
            gigsCount,
            msg.sender,
            address(0),
            _img,
            _description,
            msg.value,
            _kpis,
            false,
            false
        );

        userGigs[msg.sender].push(gigsCount);
        emit GigCreated(msg.sender, _description, msg.value);
    }

    /**
     * @notice Retrieves all created gigs.
     * @return An array of Gigs structs representing all gigs.
     */
    function getAllGigs() external view returns (Gigs[] memory) {
        require(gigsCount > 0, "No gigs yet");
        Gigs[] memory gigs = new Gigs[](gigsCount);
        for (uint256 i = 1; i <= gigsCount; i++) {
            gigs[i - 1] = allGigs[i];
        }
        return gigs;
    }

    /**
     * @notice Retrieves the details of a gig by its ID.
     * @param _gigId The ID of the gig to retrieve.
     * @return A Gigs struct representing the gig details.
     */
    function getGigById(uint256 _gigId) public view returns (Gigs memory) {
        require(_gigId > 0 && _gigId <= gigsCount, "Invalid gig ID");
        return allGigs[_gigId];
    }

    /**
     * @notice Selects a worker for a specified gig.
     * @param _gigId The ID of the gig to assign the worker to.
     * @param _appId The ID of the application submitted by the worker.
     */
    function selectWorker(uint256 _gigId, uint256 _appId) external {
        if (_gigId > gigsCount || _appId > appCount) {
            revert InvalidId();
        }

        address user = allApp[_appId].applicant;
        allGigs[_gigId].assignedApplicant = user;
        allGigs[_gigId].userSelected = true;

        emit GigAssigned(user, _gigId);
    }

    /**
     * @notice Submits an application to a specified gig.
     * @param _gigId The ID of the gig to apply to.
     * @param _coverLetter The cover letter submitted by the applicant.
     */
    function apply(uint256 _gigId, string calldata _coverLetter) external {
        if (_gigId > gigsCount) {
            revert InvalidId();
        }
        appCount++;
        allApp[appCount] = Application(
            appCount,
            _gigId,
            msg.sender,
            _coverLetter,
            false
        );
        userApplications[msg.sender].push(appCount);
    }

    /**
     * @notice Retrieves all applications submitted for a specified gig.
     * @param _gigId The ID of the gig to retrieve applications for.
     * @return An array of Application structs representing the applications.
     */
    function getGigApplications(
        uint256 _gigId
    ) public view returns (Application[] memory) {
        require(_gigId > 0 && _gigId <= gigsCount, "Invalid gig ID");
        uint256 count = 0;

        for (uint256 i = 1; i <= appCount; i++) {
            if (allApp[i].gigId == _gigId) {
                count++;
            }
        }

        Application[] memory appls = new Application[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= appCount; i++) {
            if (allApp[i].gigId == _gigId) {
                appls[index] = allApp[i];
                index++;
            }
        }

        return appls;
    }

    function getUsersGig() public view returns (Gigs[] memory) {
        uint256[] memory gigIds = userGigs[msg.sender];
        Gigs[] memory gigs = new Gigs[](gigIds.length);

        for (uint256 i = 0; i < gigIds.length; i++) {
            gigs[i] = allGigs[gigIds[i]];
        }

        return gigs;
    }

    function getUserAppl() public view returns (Application[] memory) {
        uint256[] memory appIds = userApplications[msg.sender];
        Application[] memory applications = new Application[](appIds.length);

        for (uint256 i = 0; i < appIds.length; i++) {
            applications[i] = allApp[appIds[i]];
        }

        return applications;
    }

    /**
     * @notice Payouts the bounty to the assigned worker of a specified gig.
     * @param _gigId The ID of the gig to payout.
     */
    function payout(uint256 _gigId) public onlyRole(GIG_OWNER_ROLE) {
        Gigs storage gig = allGigs[_gigId];
        require(gig.userSelected, "Worker not selected");
        require(!gig.paid, "Already paid");
        require(gig.bounty > 0, "No bounty available");

        address worker = gig.assignedApplicant;
        uint256 amount = gig.bounty;
        uint256 amountLessCom = amount / 20;

        gig.bounty = 0;
        gig.paid = true;

        (bool success, ) = worker.call{value: amountLessCom}("");
        require(success, "Transfer failed");

        emit GigPaidOut(_gigId, gig.owner, worker, amount);
    }

    /**
     * @notice Withdraws Ether from the contract by the admin.
     * @param amount The amount of Ether to withdraw.
     */
    function withdraw(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= address(this).balance, "Insufficient balance");

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Pauses contract operations.
     * Only callable by an account with the PAUSER_ROLE.
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses contract operations.
     * Only callable by an account with the PAUSER_ROLE.
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Fallback function to receive Ether.
     * Emitted when Ether is sent to the contract.
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @notice Fallback function to receive Ether with non-empty data.
     * Emitted when Ether is sent to the contract.
     */
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }
}
