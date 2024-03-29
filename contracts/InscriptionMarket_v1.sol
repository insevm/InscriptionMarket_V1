// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/lib/Struct.sol";
import "contracts/lib/Enum.sol";

contract InscriptionMarket_v1 is
    Ownable,
    EIP712,
    OrderParameterBase,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    struct OrderStatus {
        bool isValidated;
        bool isCancelled;
    }

    address public feeReceiver;
    
    // 100 / 10000
    uint256 public feeRate;

    // offerer => counter
    mapping(address => uint256) public counters;
    // order hash => status
    mapping(bytes32 => OrderStatus) public orderStatus;

    event OrderCancelled(address indexed canceller, uint256 indexed salt);
    event Sold(
        bytes32 indexed orderHash,
        uint256 indexed salt,
        uint256 indexed time,
        address from,
        address to,
        uint256 price
    );
    event SetFeeReceiver(address feeReceiver);
    event SetFeeRate(uint256 feeRate);
    event CounterIncremented(uint256 indexed counter, address indexed user);

    error OrderTypeError(ItemType offerType, ItemType considerationType);
    error InvalidCanceller();

    constructor(address owner) Ownable(owner) EIP712("insevm.trade", "v1.0.0") {}

    function _verify(
        bytes32 orderHash,
        bytes calldata signature
    ) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(orderHash);
        address signer = ECDSA.recover(digest, signature);
        return (signer);
    }

    function fulfillOrder(
        OrderParameters calldata order
    ) external payable nonReentrant {
        address from;
        address to;
        // calculate order hash
        bytes32 orderHash = _deriveOrderHash(order, counters[order.offerer]);

        require(
            block.timestamp >= order.startTime &&
                block.timestamp <= order.endTime,
            "Time error"
        );

        OrderStatus storage _orderStatus = orderStatus[orderHash];
        require(
            !_orderStatus.isCancelled && !_orderStatus.isValidated,
            "Status error"
        );

        // verify signature
        require(
            _verify(orderHash, order.signature) == order.offerer,
            "Sign error"
        );

        require(
            order.consideration.length == 1 && order.offer.length == 1,
            "Param length error"
        );

        // transfer fee
        uint256 _serviceFee;

        ConsiderationItem memory consideration = order.consideration[0];
        OfferItem memory offerItem = order.offer[0];
        if (offerItem.itemType == ItemType.NATIVE) {
            // ETH can't approve, offer's type cann't be NATIVE
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        uint256 price;
        // Consideration
        if (
            consideration.itemType == ItemType.NATIVE ||
            consideration.itemType == ItemType.ERC20
        ) {
            // check offer type, NATIVE/ERC20 <-> ERC721/ERC1155
            if (
                offerItem.itemType != ItemType.ERC721 &&
                offerItem.itemType != ItemType.ERC1155
            ) {
                revert OrderTypeError(
                    offerItem.itemType,
                    consideration.itemType
                );
            }

            _serviceFee = consideration.startAmount * feeRate / 10000;
            price = consideration.startAmount;
            if (consideration.itemType == ItemType.NATIVE) {
                require(
                    msg.value >= consideration.startAmount,
                    "TX value error"
                );
                payable(feeReceiver).transfer(_serviceFee);
                unchecked {
                    payable(consideration.recipient).transfer(
                        consideration.startAmount - _serviceFee
                    );
                }
            } else if (consideration.itemType == ItemType.ERC20) {
                IERC20(consideration.token).safeTransferFrom(
                    msg.sender,
                    feeReceiver,
                    _serviceFee
                );
                IERC20(consideration.token).safeTransferFrom(
                    msg.sender,
                    consideration.recipient,
                    consideration.startAmount - _serviceFee
                );
            }
        } else if (
            consideration.itemType == ItemType.ERC721 ||
            consideration.itemType == ItemType.ERC1155
        ) {
            if(offerItem.itemType != ItemType.ERC20){
                // other offer type is not support
                revert OrderTypeError(offerItem.itemType, consideration.itemType);
            }
            if (consideration.itemType == ItemType.ERC721) {
                IERC721(consideration.token).safeTransferFrom(
                    msg.sender,
                    consideration.recipient,
                    consideration.identifierOrCriteria
                );
            } else if (consideration.itemType == ItemType.ERC1155) {
                IERC1155(consideration.token).safeTransferFrom(
                    msg.sender,
                    consideration.recipient,
                    consideration.identifierOrCriteria,
                    consideration.startAmount,
                    "0x0"
                );
            }

            from = msg.sender;
            to = consideration.recipient;
        } else {
            // other consideration type is not support
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        // Offer
        if (offerItem.itemType == ItemType.ERC20) {
            // check consideration type
            if (
                consideration.itemType != ItemType.ERC721 &&
                consideration.itemType != ItemType.ERC1155
            ) {
                revert OrderTypeError(
                    offerItem.itemType,
                    consideration.itemType
                );
            }
            _serviceFee = offerItem.startAmount * feeRate / 10000;
            price = offerItem.startAmount;
            IERC20(offerItem.token).safeTransferFrom(
                order.offerer,
                feeReceiver,
                _serviceFee
            );
            IERC20(offerItem.token).safeTransferFrom(
                order.offerer,
                msg.sender,
                offerItem.startAmount - _serviceFee
            );
        } else if (
            offerItem.itemType == ItemType.ERC721 ||
            offerItem.itemType == ItemType.ERC1155
        ) {
            if (offerItem.itemType == ItemType.ERC721) {
                IERC721(offerItem.token).safeTransferFrom(
                    order.offerer,
                    msg.sender,
                    offerItem.identifierOrCriteria
                );
            } else if (offerItem.itemType == ItemType.ERC1155) {
                IERC1155(offerItem.token).safeTransferFrom(
                    order.offerer,
                    msg.sender,
                    offerItem.identifierOrCriteria,
                    offerItem.startAmount,
                    "0x0"
                );
            }

            from = order.offerer;
            to = msg.sender;
        } else {
            // other offer type is not support
            revert OrderTypeError(offerItem.itemType, consideration.itemType);
        }

        _orderStatus.isValidated = true;

        emit Sold(orderHash, order.salt, block.timestamp, from, to, price);
    }

    function cancel(OrderComponents[] calldata orders) external nonReentrant {
        OrderStatus storage _orderStatus;
        address offerer;

        for (uint256 i; i < orders.length; ) {
            // Retrieve the order.
            OrderComponents calldata order = orders[i];

            offerer = order.offerer;

            // Ensure caller is either offerer or zone of the order.
            if (msg.sender != offerer) {
                revert InvalidCanceller();
            }

            // Derive order hash using the order parameters and the counter.
            bytes32 orderHash = _deriveOrderHash(
                OrderParameters(
                    offerer,
                    order.offer,
                    order.consideration,
                    order.startTime,
                    order.endTime,
                    order.salt,
                    order.signature
                ),
                order.counter
            );

            // Retrieve the order status using the derived order hash.
            _orderStatus = orderStatus[orderHash];

            // Update the order status as not valid and cancelled.
            _orderStatus.isValidated = false;
            _orderStatus.isCancelled = true;

            // Emit an event signifying that the order has been cancelled.
            emit OrderCancelled(offerer, order.salt);

            // Increment counter inside body of loop for gas efficiency.
            ++i;
        }
    }

    function setFees(
        uint256 fee
    ) public onlyOwner {
        require(
            feeReceiver != address(0), "fee receiver is empty"
        );
        require(
            fee < 10000, "exceed max fee"
        );
        feeRate = fee;
        emit SetFeeRate(fee);
    }

    function setFeeReceiver(
        address receiver
    ) public onlyOwner {
        feeReceiver = receiver;
        emit SetFeeReceiver(feeReceiver);
    }
}
